# bash completion for istioctl                             -*- shell-script -*-

__istioctl_debug()
{
    if [[ -n ${BASH_COMP_DEBUG_FILE} ]]; then
        echo "$*" >> "${BASH_COMP_DEBUG_FILE}"
    fi
}

# Homebrew on Macs have version 1.3 of bash-completion which doesn't include
# _init_completion. This is a very minimal version of that function.
__istioctl_init_completion()
{
    COMPREPLY=()
    _get_comp_words_by_ref "$@" cur prev words cword
}

__istioctl_index_of_word()
{
    local w word=$1
    shift
    index=0
    for w in "$@"; do
        [[ $w = "$word" ]] && return
        index=$((index+1))
    done
    index=-1
}

__istioctl_contains_word()
{
    local w word=$1; shift
    for w in "$@"; do
        [[ $w = "$word" ]] && return
    done
    return 1
}

__istioctl_handle_reply()
{
    __istioctl_debug "${FUNCNAME[0]}"
    case $cur in
        -*)
            if [[ $(type -t compopt) = "builtin" ]]; then
                compopt -o nospace
            fi
            local allflags
            if [ ${#must_have_one_flag[@]} -ne 0 ]; then
                allflags=("${must_have_one_flag[@]}")
            else
                allflags=("${flags[*]} ${two_word_flags[*]}")
            fi
            COMPREPLY=( $(compgen -W "${allflags[*]}" -- "$cur") )
            if [[ $(type -t compopt) = "builtin" ]]; then
                [[ "${COMPREPLY[0]}" == *= ]] || compopt +o nospace
            fi

            # complete after --flag=abc
            if [[ $cur == *=* ]]; then
                if [[ $(type -t compopt) = "builtin" ]]; then
                    compopt +o nospace
                fi

                local index flag
                flag="${cur%=*}"
                __istioctl_index_of_word "${flag}" "${flags_with_completion[@]}"
                COMPREPLY=()
                if [[ ${index} -ge 0 ]]; then
                    PREFIX=""
                    cur="${cur#*=}"
                    ${flags_completion[${index}]}
                    if [ -n "${ZSH_VERSION}" ]; then
                        # zsh completion needs --flag= prefix
                        eval "COMPREPLY=( \"\${COMPREPLY[@]/#/${flag}=}\" )"
                    fi
                fi
            fi
            return 0;
            ;;
    esac

    # check if we are handling a flag with special work handling
    local index
    __istioctl_index_of_word "${prev}" "${flags_with_completion[@]}"
    if [[ ${index} -ge 0 ]]; then
        ${flags_completion[${index}]}
        return
    fi

    # we are parsing a flag and don't have a special handler, no completion
    if [[ ${cur} != "${words[cword]}" ]]; then
        return
    fi

    local completions
    completions=("${commands[@]}")
    if [[ ${#must_have_one_noun[@]} -ne 0 ]]; then
        completions=("${must_have_one_noun[@]}")
    fi
    if [[ ${#must_have_one_flag[@]} -ne 0 ]]; then
        completions+=("${must_have_one_flag[@]}")
    fi
    COMPREPLY=( $(compgen -W "${completions[*]}" -- "$cur") )

    if [[ ${#COMPREPLY[@]} -eq 0 && ${#noun_aliases[@]} -gt 0 && ${#must_have_one_noun[@]} -ne 0 ]]; then
        COMPREPLY=( $(compgen -W "${noun_aliases[*]}" -- "$cur") )
    fi

    if [[ ${#COMPREPLY[@]} -eq 0 ]]; then
        declare -F __custom_func >/dev/null && __custom_func
    fi

    # available in bash-completion >= 2, not always present on macOS
    if declare -F __ltrim_colon_completions >/dev/null; then
        __ltrim_colon_completions "$cur"
    fi

    # If there is only 1 completion and it is a flag with an = it will be completed
    # but we don't want a space after the =
    if [[ "${#COMPREPLY[@]}" -eq "1" ]] && [[ $(type -t compopt) = "builtin" ]] && [[ "${COMPREPLY[0]}" == --*= ]]; then
       compopt -o nospace
    fi
}

# The arguments should be in the form "ext1|ext2|extn"
__istioctl_handle_filename_extension_flag()
{
    local ext="$1"
    _filedir "@(${ext})"
}

__istioctl_handle_subdirs_in_dir_flag()
{
    local dir="$1"
    pushd "${dir}" >/dev/null 2>&1 && _filedir -d && popd >/dev/null 2>&1
}

__istioctl_handle_flag()
{
    __istioctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    # if a command required a flag, and we found it, unset must_have_one_flag()
    local flagname=${words[c]}
    local flagvalue
    # if the word contained an =
    if [[ ${words[c]} == *"="* ]]; then
        flagvalue=${flagname#*=} # take in as flagvalue after the =
        flagname=${flagname%=*} # strip everything after the =
        flagname="${flagname}=" # but put the = back
    fi
    __istioctl_debug "${FUNCNAME[0]}: looking for ${flagname}"
    if __istioctl_contains_word "${flagname}" "${must_have_one_flag[@]}"; then
        must_have_one_flag=()
    fi

    # if you set a flag which only applies to this command, don't show subcommands
    if __istioctl_contains_word "${flagname}" "${local_nonpersistent_flags[@]}"; then
      commands=()
    fi

    # keep flag value with flagname as flaghash
    # flaghash variable is an associative array which is only supported in bash > 3.
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        if [ -n "${flagvalue}" ] ; then
            flaghash[${flagname}]=${flagvalue}
        elif [ -n "${words[ $((c+1)) ]}" ] ; then
            flaghash[${flagname}]=${words[ $((c+1)) ]}
        else
            flaghash[${flagname}]="true" # pad "true" for bool flag
        fi
    fi

    # skip the argument to a two word flag
    if __istioctl_contains_word "${words[c]}" "${two_word_flags[@]}"; then
        c=$((c+1))
        # if we are looking for a flags value, don't show commands
        if [[ $c -eq $cword ]]; then
            commands=()
        fi
    fi

    c=$((c+1))

}

__istioctl_handle_noun()
{
    __istioctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    if __istioctl_contains_word "${words[c]}" "${must_have_one_noun[@]}"; then
        must_have_one_noun=()
    elif __istioctl_contains_word "${words[c]}" "${noun_aliases[@]}"; then
        must_have_one_noun=()
    fi

    nouns+=("${words[c]}")
    c=$((c+1))
}

__istioctl_handle_command()
{
    __istioctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"

    local next_command
    if [[ -n ${last_command} ]]; then
        next_command="_${last_command}_${words[c]//:/__}"
    else
        if [[ $c -eq 0 ]]; then
            next_command="_istioctl_root_command"
        else
            next_command="_${words[c]//:/__}"
        fi
    fi
    c=$((c+1))
    __istioctl_debug "${FUNCNAME[0]}: looking for ${next_command}"
    declare -F "$next_command" >/dev/null && $next_command
}

__istioctl_handle_word()
{
    if [[ $c -ge $cword ]]; then
        __istioctl_handle_reply
        return
    fi
    __istioctl_debug "${FUNCNAME[0]}: c is $c words[c] is ${words[c]}"
    if [[ "${words[c]}" == -* ]]; then
        __istioctl_handle_flag
    elif __istioctl_contains_word "${words[c]}" "${commands[@]}"; then
        __istioctl_handle_command
    elif [[ $c -eq 0 ]]; then
        __istioctl_handle_command
    elif __istioctl_contains_word "${words[c]}" "${command_aliases[@]}"; then
        # aliashash variable is an associative array which is only supported in bash > 3.
        if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
            words[c]=${aliashash[${words[c]}]}
            __istioctl_handle_command
        else
            __istioctl_handle_noun
        fi
    else
        __istioctl_handle_noun
    fi
    __istioctl_handle_word
}

_istioctl_authn_tls-check()
{
    last_command="istioctl_authn_tls-check"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_authn()
{
    last_command="istioctl_authn"

    command_aliases=()

    commands=()
    commands+=("tls-check")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_deregister()
{
    last_command="istioctl_deregister"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_auth_check()
{
    last_command="istioctl_experimental_auth_check"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--all")
    flags+=("-a")
    flags+=("--file=")
    two_word_flags+=("-f")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_auth()
{
    last_command="istioctl_experimental_auth"

    command_aliases=()

    commands=()
    commands+=("check")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_convert-ingress()
{
    last_command="istioctl_experimental_convert-ingress"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filenames=")
    two_word_flags+=("-f")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_dashboard_controlz()
{
    last_command="istioctl_experimental_dashboard_controlz"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--ctrlz_port=")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_dashboard_envoy()
{
    last_command="istioctl_experimental_dashboard_envoy"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_dashboard_grafana()
{
    last_command="istioctl_experimental_dashboard_grafana"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_dashboard_jaeger()
{
    last_command="istioctl_experimental_dashboard_jaeger"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_dashboard_kiali()
{
    last_command="istioctl_experimental_dashboard_kiali"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_dashboard_prometheus()
{
    last_command="istioctl_experimental_dashboard_prometheus"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_dashboard_zipkin()
{
    last_command="istioctl_experimental_dashboard_zipkin"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_dashboard()
{
    last_command="istioctl_experimental_dashboard"

    command_aliases=()

    commands=()
    commands+=("controlz")
    commands+=("envoy")
    commands+=("grafana")
    commands+=("jaeger")
    commands+=("kiali")
    commands+=("prometheus")
    commands+=("zipkin")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental_metrics()
{
    last_command="istioctl_experimental_metrics"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_experimental()
{
    last_command="istioctl_experimental"

    command_aliases=()

    commands=()
    commands+=("auth")
    commands+=("convert-ingress")
    commands+=("dashboard")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("d")
        aliashash["d"]="dashboard"
        command_aliases+=("dash")
        aliashash["dash"]="dashboard"
    fi
    commands+=("metrics")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("m")
        aliashash["m"]="metrics"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_kube-inject()
{
    last_command="istioctl_kube-inject"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filename=")
    two_word_flags+=("-f")
    flags+=("--injectConfigFile=")
    flags+=("--injectConfigMapName=")
    flags+=("--meshConfigFile=")
    flags+=("--meshConfigMapName=")
    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--valuesFile=")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_proxy-config_bootstrap()
{
    last_command="istioctl_proxy-config_bootstrap"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("-o")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_proxy-config_cluster()
{
    last_command="istioctl_proxy-config_cluster"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--direction=")
    flags+=("--fqdn=")
    flags+=("--port=")
    flags+=("--subset=")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("-o")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_proxy-config_endpoint()
{
    last_command="istioctl_proxy-config_endpoint"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    flags+=("--cluster=")
    flags+=("--port=")
    flags+=("--status=")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("-o")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_proxy-config_listener()
{
    last_command="istioctl_proxy-config_listener"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--address=")
    flags+=("--port=")
    flags+=("--type=")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("-o")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_proxy-config_route()
{
    last_command="istioctl_proxy-config_route"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--name=")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")
    flags+=("--output=")
    two_word_flags+=("-o")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_proxy-config()
{
    last_command="istioctl_proxy-config"

    command_aliases=()

    commands=()
    commands+=("bootstrap")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("b")
        aliashash["b"]="bootstrap"
    fi
    commands+=("cluster")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("c")
        aliashash["c"]="cluster"
        command_aliases+=("clusters")
        aliashash["clusters"]="cluster"
    fi
    commands+=("endpoint")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("endpoints")
        aliashash["endpoints"]="endpoint"
        command_aliases+=("ep")
        aliashash["ep"]="endpoint"
    fi
    commands+=("listener")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("l")
        aliashash["l"]="listener"
        command_aliases+=("listeners")
        aliashash["listeners"]="listener"
    fi
    commands+=("route")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("r")
        aliashash["r"]="route"
        command_aliases+=("routes")
        aliashash["routes"]="route"
    fi

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--output=")
    two_word_flags+=("-o")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_proxy-status()
{
    last_command="istioctl_proxy-status"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_register()
{
    last_command="istioctl_register"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--annotations=")
    two_word_flags+=("-a")
    flags+=("--labels=")
    two_word_flags+=("-l")
    flags+=("--serviceaccount=")
    two_word_flags+=("-s")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_validate()
{
    last_command="istioctl_validate"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--filename=")
    two_word_flags+=("-f")
    flags+=("--referential")
    flags+=("-x")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_verify-install()
{
    last_command="istioctl_verify-install"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--enableVerbose")
    local_nonpersistent_flags+=("--enableVerbose")
    flags+=("--filename=")
    flags_with_completion+=("--filename")
    flags_completion+=("__istioctl_handle_filename_extension_flag json|yaml|yml")
    two_word_flags+=("-f")
    flags_with_completion+=("-f")
    flags_completion+=("__istioctl_handle_filename_extension_flag json|yaml|yml")
    flags+=("--recursive")
    flags+=("-R")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_version()
{
    last_command="istioctl_version"

    command_aliases=()

    commands=()

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--output=")
    two_word_flags+=("-o")
    local_nonpersistent_flags+=("--output=")
    flags+=("--remote")
    local_nonpersistent_flags+=("--remote")
    flags+=("--short")
    flags+=("-s")
    local_nonpersistent_flags+=("--short")
    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

_istioctl_root_command()
{
    last_command="istioctl"

    command_aliases=()

    commands=()
    commands+=("authn")
    commands+=("deregister")
    commands+=("experimental")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("exp")
        aliashash["exp"]="experimental"
        command_aliases+=("x")
        aliashash["x"]="experimental"
    fi
    commands+=("kube-inject")
    commands+=("proxy-config")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("pc")
        aliashash["pc"]="proxy-config"
    fi
    commands+=("proxy-status")
    if [[ -z "${BASH_VERSION}" || "${BASH_VERSINFO[0]}" -gt 3 ]]; then
        command_aliases+=("ps")
        aliashash["ps"]="proxy-status"
    fi
    commands+=("register")
    commands+=("validate")
    commands+=("verify-install")
    commands+=("version")

    flags=()
    two_word_flags=()
    local_nonpersistent_flags=()
    flags_with_completion=()
    flags_completion=()

    flags+=("--context=")
    flags+=("--istioNamespace=")
    two_word_flags+=("-i")
    flags+=("--kubeconfig=")
    two_word_flags+=("-c")
    flags+=("--log_output_level=")
    flags+=("--namespace=")
    two_word_flags+=("-n")

    must_have_one_flag=()
    must_have_one_noun=()
    noun_aliases=()
}

__start_istioctl()
{
    local cur prev words cword
    declare -A flaghash 2>/dev/null || :
    declare -A aliashash 2>/dev/null || :
    if declare -F _init_completion >/dev/null 2>&1; then
        _init_completion -s || return
    else
        __istioctl_init_completion -n "=" || return
    fi

    local c=0
    local flags=()
    local two_word_flags=()
    local local_nonpersistent_flags=()
    local flags_with_completion=()
    local flags_completion=()
    local commands=("istioctl")
    local must_have_one_flag=()
    local must_have_one_noun=()
    local last_command
    local nouns=()

    __istioctl_handle_word
}

if [[ $(type -t compopt) = "builtin" ]]; then
    complete -o default -F __start_istioctl istioctl
else
    complete -o default -o nospace -F __start_istioctl istioctl
fi

# ex: ts=4 sw=4 et filetype=sh
