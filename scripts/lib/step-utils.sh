# shellcheck shell=bash
#
# Wraps script steps in a nice UI: captures output, shows a spinner with
# a rolling preview of the last few lines, and prints done/failed on finish.
# 
# Set VERBOSE=true before sourcing to skip all that and stream output raw.
#
# Usage:
#   source "$(dirname "$0")/lib/step-utils.sh"
#
#   step_begin "Do something"
#   some_command
#   step_end
#

VERBOSE="${VERBOSE:-false}"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

STEP_OUTPUT=""
STEP_LABEL=""
STEP_START=""
TAIL_PID=""
TAIL_COUNT_FILE=""
PREVIEW_LINES=5

format_duration() {
    local secs=$1
    if [ "$secs" -ge 60 ]; then
        printf "%dm %ds" $((secs / 60)) $((secs % 60))
    else
        printf "%ds" "$secs"
    fi
}

# Polls the output file and redraws the last N lines (dimmed) on the terminal.
# Uses fd 3 since stdout/stderr are redirected during a step.

tail_start() {
    TAIL_COUNT_FILE=$(mktemp)
    echo "0" > "$TAIL_COUNT_FILE"
    (
        prev_count=0
        spinner_chars='|/-\'
        spinner_i=0
        cols=$(tput cols 2>/dev/null || echo 120)
        max_width=$((cols - 4))
        while true; do
            # wipe previous tail + label line, then redraw
            for ((i=0; i<prev_count; i++)); do
                printf "\033[A\033[2K\r" >&3
            done
            printf "\033[A\033[2K\r" >&3

            printf "${CYAN}[STEP]${NC} ${STEP_LABEL}... %s\n" "${spinner_chars:spinner_i%4:1}" >&3
            spinner_i=$((spinner_i + 1))

            new_count=0
            if [ -s "$STEP_OUTPUT" ]; then
                lines=$(tail -$PREVIEW_LINES "$STEP_OUTPUT" 2>/dev/null || true)
                if [ -n "$lines" ]; then
                    new_count=$(echo "$lines" | wc -l | tr -d ' ')
                    echo "$lines" | while IFS= read -r line; do
                        printf "\033[2m  %.${max_width}s\033[0m\n" "$line" >&3
                    done
                fi
            fi

            prev_count=$new_count
            echo "$prev_count" > "$TAIL_COUNT_FILE"
            sleep 0.15
        done
    ) &
    TAIL_PID=$!
}

tail_stop() {
    if [ -n "${TAIL_PID:-}" ]; then
        kill "$TAIL_PID" 2>/dev/null || true
        wait "$TAIL_PID" 2>/dev/null || true
        TAIL_PID=""
    fi
    # clean up the preview lines left on screen
    if [ -n "${TAIL_COUNT_FILE:-}" ] && [ -f "$TAIL_COUNT_FILE" ]; then
        local count
        count=$(cat "$TAIL_COUNT_FILE")
        for ((i=0; i<count; i++)); do
            printf "\033[A\033[2K\r" >&3
        done
        rm -f "$TAIL_COUNT_FILE"
        TAIL_COUNT_FILE=""
    fi
}

step_begin() {
    STEP_LABEL="$1"
    STEP_START=$(date +%s)
    if [ "$VERBOSE" = false ]; then
        STEP_OUTPUT=$(mktemp)
        echo -e "${CYAN}[STEP]${NC} ${STEP_LABEL}..."
        exec 3>&1 4>&2 1>"$STEP_OUTPUT" 2>&1
        tail_start
    else
        echo -e "${CYAN}[STEP]${NC} ${STEP_LABEL}"
    fi
}

step_end() {
    local duration=""
    if [ -n "$STEP_START" ]; then
        duration=" ($(format_duration $(( $(date +%s) - STEP_START ))))"
    fi
    if [ "$VERBOSE" = false ]; then
        tail_stop
        exec 1>&3 2>&4 3>&- 4>&-
        printf "\033[A\033[2K\r"
        echo -e "${CYAN}[STEP]${NC} ${STEP_LABEL}... ${GREEN}done${NC}${duration}"
        rm -f "$STEP_OUTPUT"
        STEP_OUTPUT=""
    else
        echo -e "${CYAN}[STEP]${NC} ${STEP_LABEL}... ${GREEN}done${NC}${duration}"
    fi
}

on_error() {
    local duration=""
    if [ -n "${STEP_START:-}" ]; then
        duration=" ($(format_duration $(( $(date +%s) - STEP_START ))))"
    fi
    if [ "$VERBOSE" = false ] && [ -n "$STEP_OUTPUT" ] && [ -f "$STEP_OUTPUT" ]; then
        tail_stop
        exec 1>&3 2>&4 3>&- 4>&-
        printf "\033[A\033[2K\r"
        echo -e "${CYAN}[STEP]${NC} ${STEP_LABEL}... ${RED}failed${NC}${duration}"
        cat "$STEP_OUTPUT"
        rm -f "$STEP_OUTPUT"
    fi
}
trap on_error ERR

on_interrupt() {
    local duration=""
    if [ -n "${STEP_START:-}" ]; then
        duration=" ($(format_duration $(( $(date +%s) - STEP_START ))))"
    fi
    if [ "$VERBOSE" = false ] && [ -n "${STEP_OUTPUT:-}" ] && [ -f "$STEP_OUTPUT" ]; then
        tail_stop
        exec 1>&3 2>&4 3>&- 4>&-
        printf "\033[A\033[2K\r"
        echo -e "${CYAN}[STEP]${NC} ${STEP_LABEL}... ${RED}interrupted${NC}${duration}"
        rm -f "$STEP_OUTPUT"
    fi
    exit 130
}
trap on_interrupt INT TERM
