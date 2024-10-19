"""OCI image macros."""

load("@rules_oci//oci:defs.bzl", "oci_image", "oci_image_index", "oci_load", "oci_push")
load("@rules_pkg//:pkg.bzl", "pkg_tar")
load("//build_tools/transitions:multi_arch.bzl", "multi_arch")

ARCHS = [
    "amd64",
    "arm64",
]

def go_oci_image(name, base, entrypoint, srcs, repository, architectures = ARCHS, annotations = {}, remote_tags = ["latest"]):
    """go_oci_image creates a multi-arch container image from Go binary.

    Args:
        name: The name of this targes.
        base: The base image to use.
        entrypoint: The entrypoint for the container.
        srcs: Go binaries to include the image.
        repository: The repository to push the image to.
        architectures: The architectures to build for (default: ARCHS).
        annotations: The annotations to add to the image.
        remote_tags: The tags to push the image to (default: ["latest"]).
    """
    pkg_tar(
        name = name + "_pkg",
        srcs = srcs,
    )

    oci_image(
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

    oci_push(
        name = name + "_push",
        image = ":" + name + "_index",
        repository = repository,
        remote_tags = remote_tags,
    )
