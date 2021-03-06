source $stdenv/setup

mkdir -p $out/etc

set -f
sources_=($sources)
targets_=($targets)
modes_=($modes)
set +f

for ((i = 0; i < ${#targets_[@]}; i++)); do
    source="${sources_[$i]}"
    target="${targets_[$i]}"

    if [[ "$source" =~ '*' ]]; then

        # If the source name contains '*', perform globbing.
        mkdir -p $out/etc/$target
        for fn in $source; do
            ln -s "$fn" $out/etc/$target/
        done

    else
        
        mkdir -p $out/etc/$(dirname $target)
        if ! [ -e $out/etc/$target ]; then
            ln -s $source $out/etc/$target
        else
            echo "Duplicate entry $target -> $source"
            if test "$(readlink $out/etc/$target)" != "$source"; then
                echo "Mismatched duplicate entry $(readlink $out/etc/$target) <-> $source"
                exit 1
            fi
        fi
        
        if test "${modes_[$i]}" != symlink; then
            echo "${modes_[$i]}" > $out/etc/$target.mode
        fi
        
    fi
done

