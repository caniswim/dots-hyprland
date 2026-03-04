function fish_greeting
    set -l line (shuf -n 1 ~/.config/fish/quotes.txt)
    set -l parts (string split '|' $line)
    set -l quote $parts[1]
    set -l author "— $parts[2]"

    set -l W 54
    set -l border (string repeat -n (math $W + 2) "─")
    set -l empty (string repeat -n $W " ")
    set -l qlines (printf '"%s"' "$quote" | fold -s -w $W)

    echo
    set_color brblack
    echo "              ·"
    echo "             /\\"
    echo "            /  \\"
    echo "      /\\   /    \\"
    echo "     /  \\_/      \\"
    echo "  ╭$border╮"
    echo "  │ $empty │"

    for qline in $qlines
        set qline (string trim --right -- $qline)
        set -l len (string length -- "$qline")
        set -l pad (string repeat -n (math $W - $len) " ")
        echo -n "  │ "
        set_color --italic normal
        echo -n "$qline$pad"
        set_color brblack
        echo " │"
    end

    set -l alen (string length -- "$author")
    set -l apad (string repeat -n (math $W - $alen) " ")
    echo "  │ $apad$author │"
    echo "  │ $empty │"
    echo "  ╰$border╯"
    set_color normal
    echo
end
