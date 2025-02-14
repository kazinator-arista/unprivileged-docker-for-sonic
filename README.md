# What is this?

The small group of files in this project provide the basis for a Docker image and container
which can run the `sonic-buildimage` make system in an unprivileged environment,
such as the Arista Home Bus.

With these materials, `make init` and `make configure PLATFORM=vs` (for Virtual Switch)
steps have been successfully executed on Home Bus, using a `master` branch checkout of
`sonic-buildimage` from GitHub, without any patches applied.

Further tweaking inside `sonic-buildimage` is required to execute actual build steps.

# How To Use

1. This project doesn't have submodules. After cloning it, change to its top-level
   directory and obtain a `git clone` of `sonic-buildimage`.

2. Run `make` to build the container, which will be called `ubuntu-env`.

3. Run `make enter` to step into the container.

4. Then, in the container:

   i)  `cd sonic-buildimage`
   
   ii) `make init`

   iii) `make configure PLATFORM=vs`

The build should succeed, otherwise debugging is needed, likely inside `docker.sh`.

# How It Works

The `docker.sh` script is installed as `/usr/bin/docker` into the top-level
`ubuntu-env` image. The real docker is renamed `/usr/bin/real-docker`.
This script intercepts and translates `docker` commands such that

1. it propagates itself into images created with `docker build`, so that those
   images, too, will have the same script as `/usr/bin/docker`, doing so
   by dynamically editing their `Dockerfile`s; and

2. it manipulates the arguments of `docker run` to allow `sonic-buildimage`'s
   uses of Docker to succeed in the Home Bus environment, in spite of it
   ostensibly requiring privileged containers.

Also, `docker.sh` provides a side benefit:

3. when intercepting image creation, `docker.sh` coalesces runs of numerous
   consecutive `RUN` instructions into single `RUN` instructions. This
   reduces the number of image layers, and container invocations/steps
   required to build the image, speeding up the `sonic-buildimage`
   `make configure` process.

