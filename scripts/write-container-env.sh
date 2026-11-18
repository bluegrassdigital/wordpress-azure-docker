#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
    echo "Usage: write-container-env.sh <profile-file>" >&2
    exit 1
fi

# Publish one complete snapshot; partial files must never be sourced by cron.
umask 077
wordpress_env_destination=$1
wordpress_env_temporary=$(mktemp "${wordpress_env_destination}.XXXXXX")
trap 'rm -f -- "$wordpress_env_temporary"' EXIT

{
    printf '# Generated container environment. Do not edit.\n'
    /usr/bin/env -0 | while IFS= read -r -d '' wordpress_env_entry; do
        wordpress_env_name=${wordpress_env_entry%%=*}
        wordpress_env_value=${wordpress_env_entry#*=}
        if [[ ! "$wordpress_env_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            continue
        fi
        # These Bash variables cannot be restored by a login shell.
        case "$wordpress_env_name" in
            BASHOPTS|BASHPID|BASH_VERSINFO|EUID|PPID|SHELLOPTS|UID) continue ;;
        esac

        # POSIX single quotes preserve dollars, backticks, and embedded newlines.
        # An apostrophe is written as a quoted apostrophe between quoted segments.
        wordpress_env_value=${wordpress_env_value//\'/\'\\\'\'}
        printf "export %s='%s'\n" "$wordpress_env_name" "$wordpress_env_value"
    done
} > "$wordpress_env_temporary"

chmod 0600 "$wordpress_env_temporary"
mv -f -- "$wordpress_env_temporary" "$wordpress_env_destination"
trap - EXIT
