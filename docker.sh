#!/bin/bash

self=$0
this_dir=

level_zero=$([ "$self" == "./docker.sh" ] && echo y)

docker=$([ $level_zero ] && echo /usr/bin/docker || echo /usr/bin/real-docker)

docker()
{
  #printf "%s " "$docker"
  #printf "[%s] " "$@"
  #printf "\n"
  "$docker" "$@"
}

consolidate_docker_file_runs()
{
  local line=
  local runs=

  while IFS= read -r phys_line ; do
    while true ; do
      case $phys_line in
        ( '  '* )
           phys_line=${phys_line# *}
           continue
          ;;
        ( '#'* )
          ;;
        ( *\\ )
          line=$line${phys_line%\\}
          ;;
        ( * )
          line=$line$phys_line
          case $line in
          ( 'RUN '* )
            if [ -n "$runs" ] ; then
              runs="$runs && ${line#RUN }"
            else
              runs="$line"
            fi
            ;;
          ( '' )
            if [ -z "$runs" ] ; then
              printf '%s\n' "$line"
            fi
            ;;
          ( * )
            if [ -n "$runs" ] ; then
              printf '%s\n' "$runs"
              runs=
            fi
            printf '%s\n' "$line"
            ;;
          esac
          line=
      esac
      break
    done
  done

  if [ -n "$runs" ] ; then
    printf '%s\n' "$runs"
  fi
  printf '%s\n' "$line"
}

docker_build() {
  local -a args=("$@")
  local dfile=
  local i=0
  local status=0
  local last_arg=
  local context_dir=

  while [[ $i -lt ${#args[@]} ]]; do
    local arg=${args[i]}
    last_arg=$arg
    case $arg in
      ( -f | --file )
        dfile="${args[i+1]}"
        args=("${args[@]:0:i}" "${args[@]:i+2}")
        ;;
      ( --file=* )
        dfile=${arg#*=}
        args=("${args[@]:0:i}" "${args[@]:i+1}")
        ;;
      ( * )
        : $(( i++ ))
        ;;
    esac
  done

  context_dir=${last_arg-.}

  [ "$dfile" ] || dfile=$context_dir/Dockerfile

  local tmp_dfile=$context_dir/tmp.dfile
  local tmp_self=$context_dir/tmp.self

  docker_build_cleanup()
  {
    rm -f $tmp_dfile $tmp_self
    [ $1 ] && exit 1
  }

  touch $tmp_dfile || docker_build_cleanup y

  consolidate_docker_file_runs < "$dfile" > "$tmp_dfile" || docker_build_cleanup y

  if [ -z "$this_dir" ] ; then
    sed -e "s#^this_dir=#this_dir='$(realpath -P $(pwd))'#" \
        < "$self" > $tmp_self || docker_build_cleanup y
  else
    cp "$self" $tmp_self || docker_build_cleanup y
  fi

  chmod a+x $tmp_self || docker_build_cleanup y

  local last_user_line=$(awk '/^USER/ { user = $0 } END { print user }' $tmp_dfile)

  cat >> $tmp_dfile <<!
USER 0
RUN mv /usr/bin/docker /usr/bin/real-docker
COPY $(basename "$tmp_self") /usr/bin/docker
$last_user_line
!

  docker build -f $tmp_dfile "${args[@]}"
  status=$?
  docker_build_cleanup
  return $status
}

docker_run()
{
  if [ $level_zero ] ; then
    docker run "$@"
    return
  fi

  local -a args=("$@")
  local i=0

  while [[ $i -lt ${#args[@]} ]]; do
    local arg=${args[i]}
    case $arg in
      -v|--volume)
        local varg="${args[i+1]}"
        case $varg in
          ( *:* )
            local left=${varg%%:*}
            local right=${varg#*:}

            case $left in
              ( /var/* | /var )
                local subpath=${left#/var}
                local dst=${right%%:*}
                local vopts=${right#*:}
                local vopa=(${vopts//,/ })
                local mopts=
                local vo

                subpath=${subpath#/}
                args[i]=--mount

                for vo in "${vopa[@]}"; do
                  case $vo in
                    ( ro | readonly )
                       mopts=$mopts,readonly
                       ;;
                    ( private | rshared | shared | rslave | slave )
                       mopts=$mopts,bind-propagation=$vo
                       ;;
                  esac
                done

                if [ -n "$subpath" ] ; then
                  args[i+1]="type=volume,source=var_volume,dst=$dst,volume-subpath=$subpath$mopts"
                else
                  args[i+1]="type=volume,source=var_volume,dst=$dst$mopts"
                fi
                ;;
              ( $this_dir/* )
                mkdir -p "$left"
                ;;
            esac
            : $(( i += 2 ))
            ;;
          ( * )
            : $(( i++ ))
            ;;
        esac
        ;;
      ( --volume=* )
        local varg=${arg#*=}
        args=("${args[@]:0:i}" -v "$varg" "${args[@]:i+2}") 
        ;;
      ( --privileged | --privileged=true )
        args=("${args[@]:0:i}" "${args[@]:i+1}")
        ;;
      ( -d | --detach | --*=* | -i | -t | -it | --interactive | --tty | --rm | --init )
        : $(( i++ ))
        ;;
      ( --* )
        : $(( i += 2 ))
        ;;
      ( * )
        break
        ;;
    esac
  done

  docker run "${args[@]}"
}

#printf "$0 "
#printf "[%s] " "$@"
#printf "\n"

case $1 in 
  ( run ) shift; docker_run "$@" ;;
  ( build ) shift; docker_build "$@" ;;
  ( * ) docker "$@" ;;
esac
