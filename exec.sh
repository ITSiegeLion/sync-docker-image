#!/bin/bash

SCRIPT_DIR=`dirname $0`
cd $SCRIPT_DIR

CMD=
REPO=
WORKFLOW=
BRANCH="main"
INPUTS=

# 你可以在这里修改执行的默认值，请保证顺序一致
INPUT_CONFIGS=(docker.io registry.cn-beijing.aliyuncs.com)

INPUT_SHORT=()

RUN_ID=
RUN_NUMBER=

function usage() {
    echo
    echo "Usage: $0 <COMMAND> [options]"
    echo
    echo "COMMAND:"
    echo
    echo "  trigger -repo,-r <REPO> -branch,-b <BRANCH> -workflow,-w <WORKFLOW> [input]=[value]"
    echo
    echo "  copy shortcut for 'trigger -w copy.yml'"
    echo "      copy -repo,-r <REPO> -branch,-b <BRANCH> [input]=[value]"
    echo
    echo "  sync shortcut for 'trigger -w sync.yml'"
    echo "      sync -repo,-r <REPO> -branch,-b <BRANCH> [input]=[value]"
    echo
    echo "  status  -repo,-r <REPO> -workflow,-w <WORKFLOW>"
    echo
}

function r() {
    echo -e "\033[31m$1\033[0m"
}

function g() {
    echo -e "\033[32m$1\033[0m"
}

function b() {
    echo -e "\033[34m$1\033[0m"
}

function getRepo() {
    if [ -z "$REPO" ]; then
        REPO=$(git remote get-url origin | awk -F ':' '{print $2}')
        REPO=${REPO%.git}
        REPO=${REPO/https:\/\//}
    fi
}

function read_copy_config() {
    case $1 in
        source)
            INPUT_CONFIGS[0]=$2
            ;;
        destination)
            INPUT_CONFIGS[1]=$2
            ;;
        source_repo)
            INPUT_CONFIGS[2]=$2
            ;;
        destination_repo)
            INPUT_CONFIGS[3]=$2
            ;;
    esac
}

function read_sync_config() {
    case $1 in
        source)
            INPUT_CONFIGS[0]=$2
            ;;
        destination)
            INPUT_CONFIGS[1]=$2
            ;;
        source_repo)
            INPUT_CONFIGS[2]=$2
            ;;
        destination_scope)
            INPUT_CONFIGS[3]=$2
            ;;
    esac
}

function format_config() {
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    case $WORKFLOW in
        copy.yml)
            echo "[$timestamp] COPY ${INPUT_CONFIGS[0]}/${INPUT_CONFIGS[2]} ${INPUT_CONFIGS[1]}/${INPUT_CONFIGS[3]} <$1>"
            ;;
        sync.yml)
            echo "[$timestamp] SYNC ${INPUT_CONFIGS[0]}/${INPUT_CONFIGS[2]} ${INPUT_CONFIGS[1]}/${INPUT_CONFIGS[3]} <$1>"
            ;;
    esac
}

function copy() {
    WORKFLOW="copy.yml"
    trigger
}

function sync() {
    WORKFLOW="sync.yml"
    trigger
}

function trigger() {
    if [ "$INPUTS" = "" ]; then
        if [ ${#INPUT_SHORT[@]} = 2 ]; then
            if [ "$WORKFLOW" = "copy.yml" ]; then
                INPUTS="source_repo=${INPUT_SHORT[0]} destination_repo=${INPUT_SHORT[1]}"
            else
                INPUTS="source_repo=${INPUT_SHORT[0]} destination_scope=${INPUT_SHORT[1]}"
            fi
        fi
        if [ ${#INPUT_SHORT[@]} = 3 ]; then
            if [ "$WORKFLOW" = "copy.yml" ]; then
                INPUTS="destination=${INPUT_SHORT[0]} source_repo=${INPUT_SHORT[1]} destination_repo=${INPUT_SHORT[2]}"
            else
                INPUTS="destination=${INPUT_SHORT[0]} source_repo=${INPUT_SHORT[1]} destination_scope=${INPUT_SHORT[2]}"
            fi
        fi
        if [ ${#INPUT_SHORT[@]} = 4 ]; then
            if [ "$WORKFLOW" = "copy.yml" ]; then
                INPUTS="source=${INPUT_SHORT[0]} destination=${INPUT_SHORT[1]} source_repo=${INPUT_SHORT[2]} destination_repo=${INPUT_SHORT[3]}"
            else
                INPUTS="source=${INPUT_SHORT[0]} destination=${INPUT_SHORT[1]} source_repo=${INPUT_SHORT[2]} destination_scope=${INPUT_SHORT[3]}"
            fi
        fi
    fi

    params=
    inputs=($INPUTS)
    for INPUT in "${inputs[@]}"; do
        KEY=$(echo $INPUT | cut -d '=' -f 1)
        VALUE=$(echo $INPUT | cut -d '=' -f 2)
        case $WORKFLOW in
            sync.yml)
                read_sync_config $KEY $VALUE
                ;;
            copy.yml)
                read_copy_config $KEY $VALUE
                ;;
        esac
    done

    if [ "$INPUTS" != "" ]; then
        case $WORKFLOW in
            sync.yml)
                params="-f 'inputs[source]=${INPUT_CONFIGS[0]}' \
                        -f 'inputs[destination]=${INPUT_CONFIGS[1]}' \
                        -f 'inputs[source_repo]=${INPUT_CONFIGS[2]}' \
                        -f 'inputs[destination_scope]=${INPUT_CONFIGS[3]}'"
                ;;
            copy.yml)
                params="-f 'inputs[source]=${INPUT_CONFIGS[0]}' \
                        -f 'inputs[destination]=${INPUT_CONFIGS[1]}' \
                        -f 'inputs[source_repo]=${INPUT_CONFIGS[2]}' \
                        -f 'inputs[destination_repo]=${INPUT_CONFIGS[3]}'"
                ;;
        esac
    fi

    if [ "$REPO" == "" ]; then
        echo "$(r "No repository specified, use -repo or -r")"
        exit 1
    fi

    if [ "$WORKFLOW" == "" ]; then
        echo "$(r "No workflow specified, use -workflow or -w")"
        exit 1
    fi

    if [ "$INPUTS" != "" ]; then
        echo "Triggering workflow $(r $WORKFLOW) on repository $(r $REPO) with branch $(r $BRANCH) and providing the following inputs:"
        echo "$(g $(echo "${inputs[@]}" | tr ' ' ',  '))"
    else
        echo "$(r 'Inputs not specified')"
        exit 1
    fi
    read -p "Confirm? [Y/n] "
    if [[ $REPLY =~ ^[Yy]$ ]] || [ -z $REPLY ]; then
        echo "gh api \
            --method POST \
            -H \"Accept: application/vnd.github.v3+json\" \
            -H \"X-GitHub-Api-Version: 2022-11-28\" \
            /repos/$REPO/actions/workflows/$WORKFLOW/dispatches \
            -f \"ref=$BRANCH\" \
            $params
        " | sh

        if [ $? -ne 0 ]; then
            echo $(r "Failed to trigger workflow")
            exit 1 
        else
            echo $(g "Workflow Triggered")
            echo $(b "Wait to check workflow running status...")
            sleep 15
            status
        fi
    fi
}

function get_workflow_runid() {
    get_run_id_try=0
    get_run_id_cmd="gh api \
        --method GET \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        /repos/$REPO/actions/workflows/$WORKFLOW/runs \
        -f 'per_page=20'\
        --jq '.workflow_runs | map(select(.conclusion == null)) | .[0] | @text \"\(.id) | \(.run_number)\"' \
    "
    result=$(echo "$get_run_id_cmd" | sh)
    RUN_ID=($(echo "$result" | cut -d '|' -f1))
    RUN_NUMBER=($(echo "$result" | cut -d '|' -f2))
    while [ "$RUN_ID" == "" ] && [ $get_run_id_try -lt 6 ]; do
        clear
        echo "Get running id, retring $get_run_id_try/5 times..."
        get_run_id_try=$((get_run_id_try+1))
        sleep 5
        result=$(echo "$get_run_id_cmd" | sh)
        RUN_ID=($(echo "$result" | cut -d '|' -f1))
        RUN_NUMBER=($(echo "$result" | cut -d '|' -f2))
    done
}

function status() {
    get_workflow_runid
    if [ "$RUN_ID" != "" ]; then
        status_cmd="gh api \
            --method GET \
            -H 'Accept: application/vnd.github+json' \
            -H 'X-GitHub-Api-Version: 2022-11-28' \
            /repos/$REPO/actions/runs/$RUN_ID \
            --template '{{.status}} | {{.conclusion | truncate 20}} | {{.run_started_at}}'
        "
        result=$(echo $status_cmd | sh)
        status=($(echo "$result" | cut -d '|' -f1))
        conclusion=($(echo "$result"| cut -d '|' -f2))
        time=($(echo "$result" | cut -d '|' -f3))
        while [ "$status" = "in_progress" ] || [ "$status" = "" ] || [ "$conclusion" = "" ]; do
            clear
            duration=$( [ "$(uname)" = "Linux" ] && echo "$(date -d "$time" "+%s")" || echo "$(date -u -jf "%Y-%m-%dT%H:%M:%SZ" "$time" "+%s")" )
            duration=$(( $(date "+%s") - $duration ))
            if [ $duration -ge 3600 ]; then
                duration="$((duration/60))min"
            else
                duration="${duration}s"
            fi
            show_status=$( [ "$conclusion" = "" ] && echo "$status" || echo "$conclusion" )
            echo "Workflow $(g $WORKFLOW) RunID: $(b $RUN_ID) $(g $show_status) $duration"
            echo "Open https://github.com/$REPO/actions/runs/$RUN_ID view more detail"
            sleep 1
            result=$(echo $status_cmd | sh)
            status=($(echo "$result" | cut -d '|' -f1))
            conclusion=($(echo "$result"| cut -d '|' -f2))
        done
        clear
        echo "Workflow $(g $WORKFLOW) has finished with result: $( [ "$conclusion" = "success" ] && echo $(g $conclusion) || echo $(r $conclusion) )"
        if [[ "$CMD" = "trigger" || "$CMD" = "copy" || "$CMD" = "sync" ]]; then
            format_config $conclusion >> run.log
            download_log
        fi
        echo "Open https://github.com/$REPO/actions/runs/$RUN_ID view more detail"
    else
        echo "No running workflow"
    fi
}

function download_log() {
    if [ "$RUN_ID" = "" ]; then
       exit 0
    fi
    gh api \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        /repos/$REPO/actions/runs/$RUN_ID/logs > ./$RUN_ID.zip
    mkdir -p ./run_logs/
    command -v unzip > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        mv ./$RUN_ID.zip ./run_logs/$RUN_ID.zip
        echo "Log file downloaded to $SCRIPT_DIR/run_logs/$RUN_ID.zip"
        exit 0
    fi
    if [ "$WORKFLOW" = "copy.yml" ]; then
        logfile="$SCRIPT_DIR/run_logs/$(date +%Y%m%d%H%M%S)-copy-$RUN_NUMBER-$RUN_ID.log"
        unzip -p ./$RUN_ID.zip '0_copy.txt' > "$logfile"
        echo "Log file downloaded to $logfile"
    fi
    if [ "$WORKFLOW" = "sync.yml" ]; then
        logfile="$SCRIPT_DIR/run_logs/$(date +%Y%m%d%H%M%S)-sync-$RUN_NUMBER-$RUN_ID.log"
        unzip -p ./$RUN_ID.zip '0_sync.txt' > "$logfile"
        echo "Log file downloaded to $logfile"
    fi
    rm -f ./$RUN_ID.zip
}

function main() {
    gh auth status -h github.com >> /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo
        echo $(r "Need login first, you can run with following command:")
        echo
        echo $(b "gh auth login")
        echo
        exit 1
    fi
    getRepo
    $CMD
}

command -v gh > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo
    echo $(r "You need to install github cli tool.")
    echo $(r "Run with following command to install: ")
    echo
    echo $(g "curl -sS https://webi.sh/gh | sh")
    echo
    echo $(g "Visit https://github.com/cli/cli?#installation for more install instructions.")
    echo
    exit 1
fi

while [ $# -gt 0 ]; do
    case $1 in
        -repo | -r)
            shift
            REPO=$1
            ;;
        -branch | -b)
            shift
            BRANCH=$1
            ;;
        -workflow | -w)
            shift
            WORKFLOW=$1
            ;;
        trigger)
            CMD="trigger"
            ;;
        status)
            CMD="status"
            ;;
        copy)
            CMD="copy"
            ;;
        sync)
            CMD="sync"
            ;;
        *=*)
            INPUTS="$INPUTS $1 "
            ;;
        *)
            INPUT_SHORT+=($1)
            ;;
    esac
    shift
done

if [ "$CMD" = "" ] || [[ "$CMD" != "trigger" && "$CMD" != "status" && "$CMD" != "copy" && "$CMD" != "sync" ]]; then
    usage
    exit 1
fi

main