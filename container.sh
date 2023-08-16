#!/bin/bash

hugo-shell() {
    COMMAND=$(echo $1)
    if [[ "$COMMAND" == serve* ]]; then
        COMMAND="$COMMAND --bind 0.0.0.0"
    fi
    shift
    hugo-base $COMMAND $@
}

alias hugo-base="docker run --rm -p '127.0.0.1:1313:1313' -v \"\`pwd\`:/data\" -it hugo:latest"
alias hugo="hugo-shell"
