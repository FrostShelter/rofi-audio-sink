#!/usr/bin/env bash

set -u

ROFI="${ROFI:-rofi}"
WPCTL="${WPCTL:-wpctl}"

get_volume() {
    local id="$1"

    "$WPCTL" get-volume "$id" 2>/dev/null |
        awk '
            /Volume:/ {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^[0-9.]+$/) {
                        printf "%.0f", $i * 100
                        exit
                    }
                }
            }
        '
}

is_muted() {
    local id="$1"

    "$WPCTL" get-volume "$id" 2>/dev/null |
        grep -q '\[MUTED\]'
}

volume_label() {
    local id="$1"
    local volume

    volume="$(get_volume "$id")"

    if is_muted "$id"; then
        printf '    %s%% (Muted)' "$volume"
    else
        printf '    %s%%' "$volume"
    fi
}

toggle_mute() {
    "$WPCTL" set-mute "$1" toggle >/dev/null 2>&1
}

set_volume() {
    local id="$1"
    local value="$2"

    value="${value%\%}"

    [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1

    awk -v value="$value" '
        BEGIN {
            exit !(value >= 0 && value <= 100)
        }
    ' || return 1

    "$WPCTL" set-volume "$id" "${value}%"
}

edit_volume() {
    local id="$1"
    local name="$2"

    local current
    current="$(get_volume "$id")"

    local value

    value="$(
        "$ROFI" \
            -dmenu \
            -i \
            -p "$name" \
            -mesg "Enter volume level (0–100)" \
            -filter "$current" \
            -l 1
    )"

    [[ -n "$value" ]] || return 0

    if ! set_volume "$id" "$value"; then
        "$ROFI" \
            -e "Invalid volume. Enter a value from 0 to 100."
        return 0
    fi
}

get_prop() {
    local id="$1"
    local property="$2"

    "$WPCTL" inspect "$id" -r 2>/dev/null |
        sed -n "s/.*${property} = \"\(.*\)\"/\1/p" |
        head -n 1
}

get_node_name() {
    local id="$1"

    local name

    name="$(get_prop "$id" "node.description")"

    [[ -n "$name" ]] ||
        name="$(get_prop "$id" "node.name")"

    [[ -n "$name" ]] ||
        name="Unknown"

    printf '%s' "$name"
}

get_default_sink() {
    "$WPCTL" status |
        awk '
            /Sinks:/ {
                section=1
                next
            }

            /Sources:/ {
                section=0
            }

            section && /\*/ {
                if (match($0, /[0-9]+[.]?[[:space:]]+/)) {
                    id=substr($0, RSTART, RLENGTH)
                    gsub(/[[:space:].]/, "", id)
                    print id
                    exit
                }
            }
        '
}

list_output_devices() {
    "$WPCTL" status |
        awk '
            /Sinks:/ {
                section = 1
                next
            }

            /Sources:/ {
                section = 0
            }

            section {
                line = $0

                if (match(line, /[0-9]+[.][[:space:]]+/)) {
                    id = substr(line, RSTART, RLENGTH)
                    gsub(/[^0-9]/, "", id)

                    name = substr(line, RSTART + RLENGTH)

                    gsub(/^[*│├└─[:space:]]+/, "", name)
                    gsub(/[[:space:]]+\[.*$/, "", name)
                    gsub(/[[:space:]]+$/, "", name)

                    if (id ~ /^[0-9]+$/ && name != "")
                        print id "\t" name
                }
            }
        '
}

output_devices() {
    while true; do
        local labels=()
        local ids=()

        while IFS=$'\t' read -r id name; do
            [[ "$id" =~ ^[0-9]+$ ]] || continue

            local icon="   "

            if [[ "$name" =~ [Bb]luetooth|[Hh]eadset|[Hh]eadphones|[Ee]arbuds ]]; then
                icon="🎧   "
            elif [[ "$name" =~ HDMI|DisplayPort ]]; then
                icon="   "
            fi

            local marker=""

            if [[ "$id" == "$(get_default_sink)" ]]; then
                marker="   ✓"
            fi

            labels+=("$icon $name$marker")
            ids+=("$id")

        done < <(list_output_devices)

        if ((${#labels[@]} == 0)); then
            "$ROFI" \
                -e "No output devices found."
            return
        fi

        labels+=("    Back")

        local selected

        selected="$(
            printf '%s\n' "${labels[@]}" |
                "$ROFI" \
                    -dmenu \
                    -i \
                    -p "Output Devices" \
                    -format i \
                    -l 11
        )" || return

        [[ "$selected" =~ ^[0-9]+$ ]] || return

        local index="$selected"

        if ((index == ${#labels[@]} - 1)); then
            return
        fi

        ((index < ${#ids[@]})) || continue

        "$WPCTL" set-default "${ids[$index]}" >/dev/null 2>&1
    done
}

list_playback_streams() {
    "$WPCTL" status |
        awk '
            /Streams:/ {
                section = 1
                next
            }

            section && /^[[:space:]]*[^│├└─[:space:]][^0-9]*$/ {
                next
            }

            section {
                line = $0

                if (match(line, /^[[:space:]]*[0-9]+[.][[:space:]]+/)) {
                    prefix = substr(line, 1, RSTART + RLENGTH - 1)

                    if (line !~ /^[[:space:]]{8}[0-9]+[.][[:space:]]+/)
                        next

                    id = prefix
                    gsub(/[^0-9]/, "", id)

                    name = substr(line, RSTART + RLENGTH)
                    gsub(/[[:space:]]+$/, "", name)

                    if (id ~ /^[0-9]+$/ && name != "")
                        print id "\t" name
                }
            }
        '
}

build_playback_list() {
    local default_sink

    default_sink="$(get_default_sink)"

    if [[ -n "$default_sink" ]]; then
        local system_volume

        system_volume="$(volume_label "$default_sink")"

        printf '%s\t%s\n' \
            "System Sounds  $system_volume" \
            "$default_sink"
    fi

    while IFS=$'\t' read -r id name; do
        [[ "$id" =~ ^[0-9]+$ ]] || continue

        local media_class

        media_class="$(
            "$WPCTL" inspect "$id" -r 2>/dev/null |
                sed -n 's/.*media.class = "\(.*\)"/\1/p' |
                head -n 1
        )"

        [[ "$media_class" == "Stream/Output/Audio" ]] ||
            [[ "$media_class" == "Audio/Stream" ]] ||
            continue

        local volume

        volume="$(volume_label "$id")"

        printf '%s\t%s\n' \
            "$name  $volume" \
            "$id"

    done < <(list_playback_streams)
}

playback_actions() {
    local id="$1"
    local name="$2"

    while true; do
        local volume

        volume="$(volume_label "$id")"

        local mute_action

        if is_muted "$id"; then
            mute_action="    Unmute"
        else
            mute_action="    Mute"
        fi

        local selected

        selected="$(
            printf '%s\n' \
                "Volume: $volume" \
                "$mute_action" \
                "    Back" |
                "$ROFI" \
                    -dmenu \
                    -i \
                    -p "$name" \
                    -format i \
                    -l 3
        )" || return

        case "$selected" in
            0)
                edit_volume "$id" "$name"
                ;;

            1)
                toggle_mute "$id"
                ;;

            2|*)
                return
                ;;
        esac
    done
}

playback_menu() {
    while true; do
        local labels=()
        local ids=()

        while IFS=$'\t' read -r label id; do
            [[ -n "$id" ]] || continue

            labels+=("$label")
            ids+=("$id")

        done < <(build_playback_list)

        if ((${#labels[@]} == 0)); then
            "$ROFI" \
                -e "No playback devices or applications found."
            return
        fi

        labels+=("    Back")

        local selected

        selected="$(
            printf '%s\n' "${labels[@]}" |
                "$ROFI" \
                    -dmenu \
                    -i \
                    -p "Playback" \
                    -format i \
                    -l 11
        )" || return

        [[ "$selected" =~ ^[0-9]+$ ]] || return

        local index="$selected"

        if ((index == ${#labels[@]} - 1)); then
            return
        fi

        ((index < ${#ids[@]})) || continue

        playback_actions \
            "${ids[$index]}" \
            "${labels[$index]}"
    done
}

main() {
    while true; do

        local selected

        selected="$(
            printf '%s\n' \
                "▶  Playback" \
                "    Output Devices" |
                "$ROFI" \
                    -dmenu \
                    -i \
                    -p "Audio" \
                    -format i \
                    -l 2
        )" || exit 0

        [[ "$selected" =~ ^[0-9]+$ ]] || exit 0

        case "$selected" in
            0)
                playback_menu
                ;;

            1)
                output_devices
                ;;
        esac

    done
}

main
