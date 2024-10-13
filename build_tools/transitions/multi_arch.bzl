"a rule transitioning an oci_image to multiple platforms"

def _multiarch_transition(settings, attr):
    return [
        # 指定されたplatformsをビルド時のコマンドラインオプションとして指定
        {"//command_line_option:platforms": str(platform)}
        for platform in attr.platforms
    ]

multiarch_transition = transition(
    implementation = _multiarch_transition,
    inputs = [],
    outputs = ["//command_line_option:platforms"],
)

def _impl(ctx):
    return DefaultInfo(files = depset(ctx.files.target))

multi_arch = rule(
    implementation = _impl,
    attrs = {
        "target": attr.label(cfg = multiarch_transition),
        "platforms": attr.label_list(),
        # このルールを使えるパッケージの許可リストを設定できる。
        # ここでは全て許可するようになっている。
        # transitionの追加はビルドの依存グラフを簡単に大きくしてしまえるため、
        # こういった保護機構があるらしい。
        # https://bazel.build/versions/7.0.0/extending/config#user-defined-transitions
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)
