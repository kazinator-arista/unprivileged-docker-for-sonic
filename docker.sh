#!/bin/bash

#
# "Docker Virus" wrapper script.
#
# In our top-level environment outside of our container, we run this
# directly as ./docker.sh.  This is "level zero", and the level_zero
# variable is set to y, to distinguish some behaviors.
#
# Inside our container, this script becomes /usr/bin/docker, and
# the real docker executable is moved to /usr/bin/real-docker.
#
# This script intercepts all docker commands and modifies the behavior
# of some of them. docker build commands are handled via the docker_build
# function, and docker run through docker_run. All other commands are
# transparent.
#

# variable $self: assumed to be a path to this script.
self=$0

# variable $this_dir: points to the image-build-time current directory
#
# The variable is used docker_run to handle a certain case of a missing
# directory being mapped.
#
# This is tricky. Note that the variable is assigned a blank value in
# the master copy of this script. When the "virus" propagates itself,
# it filters its own source code, editing this line.
this_dir=

# variable $level_zero: set to y in the top-level invocation, otherwise blank.
level_zero=$([ "$self" == "./docker.sh" ] && echo y)

# Variable $docker: the real docker program that WE use.
#
# In level zero, we use /usr/bin/docker. In the nested levels, when we
# have propagated as a "virus" into containers whose creation we intercepted,
# we ARE /usr/bin/docker, and real docker is /usr/bin/real-docker
docker=$([ $level_zero ] && echo /usr/bin/docker || echo /usr/bin/real-docker)

# Function docker(): call the real docker. We indirect through here so
# that we can add debugging statements to trace docker commands.
docker()
{
  #printf "%s " "$docker"
  #printf "[%s] " "$@"
  #printf "\n"
  "$docker" "$@"
}

# Function consolidate_docker_file_runs(): optimize batches of RUN commands.
#
# sonic-buildimage Dockerfiles contain some long sequences of simple RUN
# instrudctions which often only execute a single command, such as "apt-get
# install package" or "pip3 install package". This is inefficient because each
# RUN instruction creates an image layer, and runs in a new build-time
# temporary container. We consolidate consecutive RUN instruction into a single
# RUN with multiple commands joined by &&.
consolidate_docker_file_runs()
{
  local line=     # logical line accumulator
  local runs=     # accumulator for consolidated RUN line we are building
  local phys_line # physical line of the file

  while IFS= read -r phys_line ; do
    # This loop is for eating spaces from the start of $phys_line,
    # or any other iterative processing we might want to apply to $phys_line.
    # It repeats only when an explicit continue is given; there is a break
    # statement at the bottom.
    while true ; do
      case $phys_line in
        # if the physical line starts with two spaces, eat one of them
        # and continue the "while true" loop, to repeat this if necessary
        ( '  '* )
           phys_line=${phys_line# *}
           continue
          ;;
        # we consume and discard comment lines. Dockerfiles have a feature:
        # long logical lines made using backslash continuation can contain
        # comment lines, and these comment lines don't need backslashes.
        ( '#'* )
          ;;
        # Physical line with backslash continuation: we add it to line,
        # and get another physical line.
        ( *\\ )
          line=$line${phys_line%\\}
          ;;
        # Main case: non-continued line.
        ( * )
          # Finalize line by adding last piece and categorize.
          line=$line$phys_line
          case $line in
          # We have a RUN line. This either starts a new run consolidation,
          # or continues and existing one.
          ( 'RUN '* )
            if [ -n "$runs" ] ; then
              # remove 'RUN ' prefix and add to existing command with &&
              runs="$runs && ${line#RUN }"
            else
              # start new consolidation by taking the whole thing
              runs="$line"
            fi
            ;;
          # Empty line: we pass these through to the output if we are not in
          # the middle of accumulating a run consolidation, otherwise we throw
          # them away.
          ( '' )
            if [ -z "$runs" ] ; then
              printf '%s\n' "$line"
            fi
            ;;
          # Non-blank, non-RUN line: we output the line. But before it,
          # if we have accumulated a RUN consolidation, we output that first,
          # and clear the accumulator.
          ( * )
            if [ -n "$runs" ] ; then
              printf '%s\n' "$runs"
              runs=
            fi
            printf '%s\n' "$line"
            ;;
          esac

          # After processing the line, clear the line accumulator.
          line=
      esac
      break # break out of while true loop
    done
  done

  # When we run out of input, we output any RUN consolidation that we had
  # going, and flush out any line
  # Note that if the file ends in the middle of an backslash continuation,
  # i.e. unterminated logical line, that line will not be subject to any
  # special processing. If it is a RUN, it won't be added to the consolidation.
  if [ -n "$runs" ] ; then
    printf '%s\n' "$runs"
  fi
  printf '%s\n' "$line"
}

# Function docker_build(): wrap the docker build command
# Two unrelated goals here are:
# - propagate the "docker virus" (this script) into new images
# - optimize RUN commands in the Dockerfile that passes through us
docker_build() {
  local -a args=("$@")    # args to Bash array for easy, accurate manipulation
  local dfile=            # Name of Dockerfile inferred from build arguments
  local i=0               # argument index for while loop
  local status=0          # termination status of real docker command
  local last_arg=         # holds last build argument after first loop
  local context_dir=      # holds docker build context

  # Sweep through arguments to determine where the Dockerfile is coming
  # from, and remove that reference form the arguments
  while [[ $i -lt ${#args[@]} ]]; do
    local arg=${args[i]}
    last_arg=$arg
    case $arg in
      # If we see -f, we assume we have -f ARG, and the Dockerfile is ARG.
      # We remove that pair of arguments.
      ( -f | --file )
        dfile="${args[i+1]}"
        args=("${args[@]:0:i}" "${args[@]:i+2}")
        ;;
      # If we see --file-ARG, we delete that argument, and assume that
      # the Dockerfile is ARG.
      ( --file=* )
        dfile=${arg#*=}
        args=("${args[@]:0:i}" "${args[@]:i+1}")
        ;;
      # For any other argument, we increment by one.
      # This is not strictly correct; it leaves us open to
      # misinterpreting the argument of an option as an option,
      # if it looks like one. This program is for a specific use case
      # in a particular aspect of single project, not for the world
      # at large, or academic publication.
      ( * )
        : $(( i++ ))
        ;;
    esac
  done

  # The docker build context is the last argument. If it is missing,
  # we default to the current directory, . (dot).
  context_dir=${last_arg-.}

  # If we didn't detect the identify of the Dockerfile from the
  # docker build arguments, we must default it the same as docker does:
  # it is assumed to be a file named Dockerfile, in the build context dir.
  [ "$dfile" ] || dfile=$context_dir/Dockerfile

  # Important: these temp files mus tbe in the context_dir, because
  # the the Dockerfile COPY instruction references them:
  local tmp_dfile=$context_dir/tmp.dfile  # filtered copy of Dockerfile
  local tmp_self=$context_dir/tmp.self    # filtered copy of this script itself

  # Function docker_build_cleanup(): we pretend this is local to docker_build.
  # We call this before returning, or if the shell happens to exit.
  # If given a nonblank argument, this function exits the shell, with
  # a failed termination status.
  docker_build_cleanup()
  {
    rm -f $tmp_dfile $tmp_self
    [ $1 ] && exit 1
  }

  # If we cannot create the temporary file, we bail.
  touch $tmp_dfile || docker_build_cleanup y

  # Filter Dockerfile to temp, consolidating the RUN instructions
  consolidate_docker_file_runs < "$dfile" > "$tmp_dfile" || docker_build_cleanup y

  # If we are the the zero-level invocation with the empty "this_dir="
  # assignment, we filter this script, to add the current directory to that
  # assignment. We put it into single quotes, praying it doesn't contain one.
  # If we are a recursive invocation of the propagated "docker virus", then
  # we just copy ourselves.
  if [ -z "$this_dir" ] ; then
    sed -e "s#^this_dir=#this_dir='$(realpath -P $(pwd))'#" \
        < "$self" > $tmp_self || docker_build_cleanup y
  else
    cp "$self" $tmp_self || docker_build_cleanup y
  fi

  # We make sure that the copy we made of ourself is executable.
  chmod a+x $tmp_self || docker_build_cleanup y

  # variable $last_user_line: last line of Dockerfile with USER instruction.
  #
  # We need this line because we are going to add a USER 0 line to the
  # Dockerfile, in order to execute, with privilege, a RUN command that
  # we will also be adding. After that, we must again specify to the original
  # USER that Dockerfile wants.
  local last_user_line=$(awk '/^USER/ { user = $0 } END { print user }' $tmp_dfile)

  # We now append material to the Dockerfile we have copied/filtered.
  #
  # - We add USER 0 to switch to an image layer in which the build-time
  #   container is running as root.
  # - We add a RUN mv ... command to move the docker executable.
  # - We add a COPY to pull in our "docker virus" script in as /usr/bin/docker
  # - We add the original Docker script's last USER line to recover the
  #   default user ID which it wants containers to use.
  cat >> $tmp_dfile <<!
USER 0
RUN mv /usr/bin/docker /usr/bin/real-docker
COPY $(basename "$tmp_self") /usr/bin/docker
$last_user_line
!

  # Now we call the real docker, passing the filtered Dockerfile with the
  # -f argument, and the filtered args. We have removed all -f and --file
  # arguments from args, so we the -f we are adding is the only one:
  # docker is taking the altered Dockerfile we have produced.
  docker build -f $tmp_dfile "${args[@]}"  # docker is our function, above!

  # Blow away temporary files, and propagate the status that docker returned.
  status=$?
  docker_build_cleanup
  return $status
}

# Function docker_build(): wrap the docker run command
#
# The goal here is to do whatever it takes so that the docker containers
# created by sonic-buildimage run in the home-bus, or similar environment.
#
# The environment is characterized by:
# - lack of privilege: docker --privilege doesn't work
# - docker container not running its own docker daemon:
#   - docker containers created within, when requesting paths to be mounted,
#     request them from the file namespace of our docker daemon, not
#     our namespace.
#     - in particular, this affects the /var/* mounts sonic-buildimage wants
docker_run()
{
  # If we are running outside of our container, we go straight to the real
  # docker; we don't need to translate the docker run command in our own
  # Makefile.
  if [ $level_zero ] ; then
    docker run "$@"
    return
  fi

  local -a args=("$@")    # args to Bash array for easy, accurate manipulation
  local i=0               # argument index for while loop

  # Sweep through arguments, looking for things to rewrite or delete,
  # to prepare the arguments we will hand off to the real docker.
  while [[ $i -lt ${#args[@]} ]]; do
    local arg=${args[i]}
    case $arg in
      # We rewrite certain cases of -v ARG or --volume ARG
      ( -v | --volume )
        local varg="${args[i+1]}"
        case $varg in
          # -v LEFT:RIGHT case: RIGHT can itself have colon, e.g. DST:VOPTS
          ( *:* )
            local left=${varg%%:*}
            local right=${varg#*:}

            case $left in
              # LEFT specifies a path in /var space. If we do not transform
              # this, it will be requesting or docker daemon's /var, which is
              # not the /var in our top-level container.
              #
              # We have made sure that our /var is actually a named DOcker
              # volume called var_volume. We will rewrite the /var
              # references to refer to var_volume.
              ( /var/* | /var )
                local subpath=${left#/var}  # subpath, e.g. /var/run -> /run
                local dst=${right%%:*}      # dest: right part before colon
                local vopts=${right#*:}     # opts: right part after colon
                local vopa=(${vopts//,/ })  # opts split on commas into array
                local mopts=                # opts translated to --mount syntax
                local vo                    # loop iteration variable

                subpath=${subpath#/}  # trim leading slash from subpath
                args[i]=--mount       # translate -v or --volume to --mount

                # loop over options, translating from -v options to
                # --mount options, as best as possible.
                # The options go into the $mopts string, which is
                # either empty, or begins with a comma.
                for vo in "${vopa[@]}"; do
                  case $vo in
                    # ro or readonly maps to readonly
                    ( ro | readonly )
                       mopts=$mopts,readonly
                       ;;
                    # the following option words are supported in --mount,
                    # as arguments of bind-propagation:
                    ( private | rshared | shared | rslave | slave )
                       mopts=$mopts,bind-propagation=$vo
                       ;;
                  esac
                done

                # if /var/something... was specified then we have a subpath,
                # and we generate a --mount argument that uses volume-subpath=
                # to specify the subpath of /var to be mounted at the
                # destination. Otherwise we omit that. $mopts is either
                # empty or begins with a comma, so we need no comma before it.
                if [ -n "$subpath" ] ; then
                  args[i+1]="type=volume,source=var_volume,dst=$dst,volume-subpath=$subpath$mopts"
                else
                  args[i+1]="type=volume,source=var_volume,dst=$dst$mopts"
                fi
                ;;
              # This rule handles a situation when a volume mount is requested
              # from a nonexistent source directory within our tree.
              # Any path that we see in our tree, we run "mkdir -p".
              # If we don't do this, the docker daemon will try doing the same
              # thing. That will fail when our tree is NFS-mounted, because
              # docker is running as root, and cannot manipulate non-root NFS
              # material. Requesting a nonexistent directory is likely
              # unintentinal. There is a $(mkdir -p ...) expression in one of
              # the sonic-buildimage Makefiles which should be
              # $(shell mkdir -p ...).
              ( $this_dir/* )
                mkdir -p "$left"
                ;;
            esac
            # After handling -v or --volume with a LEFT:RIGHT argument, go
            # forward two arguments.
            : $(( i += 2 ))
            ;;
          ( * )
            # fixme: here we are assuming that if the argument of -v or
            # --volume does not have LEFT:RIGHT form (colon present),
            # then it's not an argument, and we only advance past the
            # option. Someone change thiw to i += 2 and test, please. :)
            : $(( i++ ))
            ;;
        esac
        ;;
      # When we see a --volume=ARG argument, we explode it into a
      # -v ARG argument pair, and continue the loop at the same [i] position.
      ( --volume=* )
        local varg=${arg#*=}
        args=("${args[@]:0:i}" -v "$varg" "${args[@]:i+2}")
        ;;
      # We delete any --privileged option. Nonstarter in our env.
      ( --privileged | --privileged=true )
        args=("${args[@]:0:i}" "${args[@]:i+1}")
        ;;
      # In this case, we recognize various options or option combinations that
      # do not take an additional argument, then skip them with i++.
      ( -d | --detach | --*=* | -i | -t | -it | --interactive | --tty | --rm | --init )
        : $(( i++ ))
        ;;
      # Any options not handled by the previous case, whether long or short
      # options are assummed to have an argument which is skipped.
      ( --* | -* )
        : $(( i += 2 ))
        ;;
      # Assuming we have correctly recognized options and their arguments,
      # we bail the loop when we see a non-option argument. This must be
      # the IMAGE argument, possibly followed by a command.
      ( * )
        break
        ;;
    esac
  done

  # call the docker function, which calls real docker, with our
  # transformed arguments.
  docker run "${args[@]}"
}

#printf "$0 "
#printf "[%s] " "$@"
#printf "\n"

# Master docker command dispatch
# Note that the processed cases delete the command word;
# the functions add it back when calling docker.
case $1 in
  ( run ) shift; docker_run "$@" ;;
  ( build ) shift; docker_build "$@" ;;
  ( * ) docker "$@" ;;
esac
