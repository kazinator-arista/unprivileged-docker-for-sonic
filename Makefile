# variable $(this_dir): the directory where this Makefile project resides.
#
# It is mapped into the ubuntu-env docker container under an identical path.
# We use identical paths because inside the container we create, there will be
# more containers created. When they map their own paths, they are actually
# requesting them from the same docker daemon that we are using. That daemon
# does not see paths that have been remapped within a container.
this_dir := $(shell pwd)

# variable $(docker_image): the name of the Docker image we build here.
docker_image := ubuntu-env

# variable (socker): docker program to use: our replacement shell script.
docker := ./docker.sh

# pattern rule used for building Dockerfile from Dockerfile.in The .in file
# contains shell here-document material, which we combine with a header and
# footer to make a complete here-document script, which we then execute. Its
# output is captured as the target file.
%: %.in
	printf "cat <<__HERE_DOC_END__\n" > $@.tmp
	printf "# This file is GENERATED from Dockerfile.in!\n" >> $@.tmp
	cat $< >> $@.tmp
	printf "__HERE_DOC_END__\n" >> $@.tmp
	rm -f $@
	bash $@.tmp > $@
	chmod -w $@
	rm -f $@.tmp

# target $(docker_image): build image from Dockerfile
#
.PHONY: $(docker_image)
$(docker_image): Dockerfile
	$(docker) build -t -f $< $@ .

# target enter: create interactive container from $(docker_image)
#
# Important details:
#
# - We map a volume called var_volume to /var. In our Dockerfile, there is a
#   VOLUME /var mount point for this. If var_volume does not exist, Docker will
#   create it. This /var mount is absolutely crucial, because the
#   sonic-buildimage Dockerfiles map /var paths. Our docker.sh script
#   intercepts /var mounts, and rewrites them to refer to var_volume. This
#   trick allows the inner Docker containers to map *our* var; without this
#   they are requesting /var from our docker daemon and its environment.
#
# - We propagate the docker socket to /var/run/docker.sock
#
# - We mount this directory itself under an identical path in the container.
#   When the container itself uses docker commands to map paths into its own
#   docker images, this simple equivalence allows them to resolve. See comment
#   about $(this_dir) above.
.PHONY: enter
enter:
	$(docker) run \
	  -it \
	  --rm \
	  -v var_volume:/var \
	  -v $(this_dir):$(this_dir) \
	  -v /var/run/dockersocket/docker.sock:/var/run/docker.sock \
	  $(docker_image)
