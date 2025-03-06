# What is this?

The small group of files in this project provide the basis for a Docker image and container
which can run the `sonic-buildimage` make system in an unprivileged environment,
such as the Arista Home Bus.

With these materials, `make init` and `make configure PLATFORM=vs` (for Virtual Switch)
steps have been successfully executed on Home Bus, using a `master` branch checkout of
`sonic-buildimage` from GitHub, without any patches applied.

Further tweaking inside `sonic-buildimage` is required to execute actual build steps.
See Sonic-Buildimage Patch section below.

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

# Sonic-Buildimage Patch

The file `sonic-buildimage.patch` contains a small number of changes
to the makefiles `rules/functions` and `slave.mk`. These patches were
made against commit `bb320c229ee7e381b18f60a2e91f37aa4fad5564`, dated
February 4, on the `sonic-buildimage` `master` branch.

The Sonic-Buildimage build system tries to perpetrate a few tricks
which require superuser privilege. In one case, it wants to make one
directory of Debian packages appear elsewhere using `mount --bind`. The patch
changes this to just using a symbolic link.

In another situation, the build system tries to set up a Linux
overlayfs for a certain `dpkg` directory, such that the build system
can make changes which can be rolled back. The patch changes the
implementation to instead create a `cp -a` copy of the to-be-overlaid
lower directory to a temporarly location, pointing the build system
to that directory.

With these changes, the `make PLATFORM=vs configure` step will pass,
producing all the Debian-based docker images that the build needs.
The actual build can be started. Where it fails is that the build
wants to execute tests of the `libnl` package. Those tests require kernel
privilege; they cannot be run in an unprivileged Docker container.
A patch is needed to skip some (or all) of these tests.
