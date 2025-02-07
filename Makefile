this_dir := $(shell pwd)

docker_image := ubuntu-env

docker := ./docker.sh

%: %.in
	printf "cat <<__HERE_DOC_END__\n" > $@.tmp
	printf "# This file is GENERATED from Dockerfile.in!\n" >> $@.tmp
	cat $< >> $@.tmp
	printf "__HERE_DOC_END__\n" >> $@.tmp
	rm -f $@
	bash $@.tmp > $@
	chmod -w $@
	rm -f $@.tmp

.PHONY: $(docker_image)
$(docker_image): Dockerfile
	$(docker) build -t -f $< $@ .

.PHONY: enter
enter:
	$(docker) run \
	  -it \
	  --rm \
	  -v var_volume:/var \
	  -v $(this_dir):$(this_dir) \
	  -v /var/run/dockersocket/docker.sock:/var/run/docker.sock \
	  $(docker_image)
