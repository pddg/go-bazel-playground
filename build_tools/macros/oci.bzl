"""OCI image macros."""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_image_index", "oci_load", "oci_push")
load("@rules_pkg//:pkg.bzl", "pkg_tar")
load("@aspect_bazel_lib//lib:expand_template.bzl", "expand_template")
load("//build_tools/transitions:multi_arch.bzl", "multi_arch")

ARCHS = [
    "amd64",
    "arm64",
]

def oci_image_with_known_annotations(
    name,
    base,
    entrypoint,
    tars,
    annotations = {},
):
    """oci_image_with_known_annotations creates a container image with known annotations.

    following annotations are added by default:
    - org.opencontainers.image.source
    - org.opencontainers.image.version
    - org.opencontainers.image.revision
    - org.opencontainers.image.created

    Obtain the value of these annotations from the build environment.
    - VERSION: Version number of the build.
    - GIT_SHA: Git commit hash of the build.
    - BUILD_TIMESTAMP_ISO8601: Timestamp of the build in ISO8601 format.

    Args:
        name: The name of this target.
        base: The base image to use.
        entrypoint: The entrypoint for the container.
        tars: The tarballs to include in the image.
        annotations: The annotations to add to the image.
    """
    expand_template(
        name = name + "_annotations",
        out = "_stamped.annotations.txt",
        template = [
            "org.opencontainers.image.source=https://github.com/pddg/go-bazel-playground",
            "org.opencontainers.image.version=nightly",
            "org.opencontainers.image.revision=devel",
            "org.opencontainers.image.created=1970-01-01T00:00:00Z",
        ] + [
            "{}={}".format(key, value) for (key, value) in annotations.items()
        ],
        stamp_substitutions = {
            "devel": "{{GIT_SHA}}",
            "nightly": "{{VERSION}}",
            "1970-01-01T00:00:00Z": "{{BUILD_TIMESTAMP_ISO8601}}",
        },
    )
    oci_image(
        name = name,
        base = base,
        entrypoint = entrypoint,
        tars = tars,
        annotations = ":" + name + "_annotations",
        labels = ":" + name + "_annotations",
    )


def oci_push_with_version(
    name,
    image,
    repository,
):
    """oci_push_with_stamped_tags pushes an image with stamped tags.

    Args:
        name: The name of this target.
        image: The image to push.
        repository: The repository to push the image to.
    """
    expand_template(
        name = name + "_tags",
        out = "_stamped.tags.txt",
        template = ["latest"],
        stamp_substitutions = {
            "latest": "{{VERSION}}",
        },
    )
    oci_push(
        name = name,
        image = image,
        repository = repository,
        remote_tags = ":" + name + "_tags",
    )


def go_oci_image(name, base, entrypoint, srcs, repository, architectures = ARCHS, annotations = {}):
    """go_oci_image creates a multi-arch container image from Go binary.

    Args:
        name: The name of this targes.
        base: The base image to use.
        entrypoint: The entrypoint for the container.
        srcs: Go binaries to include the image.
        repository: The repository to push the image to.
        architectures: The architectures to build for (default: ARCHS).
        annotations: The annotations to add to the image.
    """
    pkg_tar(
        name = name + "_pkg",
        srcs = srcs,
    )

    oci_image_with_known_annotations(
        name = name,
        base = base,
        entrypoint = entrypoint,
        tars = [":" + name + "_pkg"],
        annotations = annotations,
    )

    for arch in architectures:
        multi_arch(
            name = name + "_" + arch,
            target = ":" + name,
            platforms = [
                "@rules_go//go/toolchain:linux_" + arch,
            ],
        )

    oci_image_index(
        name = name + "_index",
        images = [":" + name + "_" + arch for arch in architectures],
    )

    oci_load(
        name = name + "_load",
        image = select({
          "@platforms//cpu:x86_64": ":" + name + "_amd64",
          "@platforms//cpu:arm64": ":" + name + "_arm64",
        }),
        repo_tags = [repository + ":latest"],
    )

    oci_push_with_version(
        name = name + "_push",
        image = ":" + name + "_index",
        repository = repository,
    )
