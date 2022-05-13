#!/usr/bin/env bash
set -xo pipefail

get_os() {
	unameOut="$(uname -s)"
	case "${unameOut}" in
		Darwin*)    machine=darwin;;
		*)          machine="linux"
	esac
	echo ${machine}
}

get_architecture() {
	unameOut="$(uname -m)"
	case "${unameOut}" in
		i386)   architecture="386" ;;
		i686)   architecture="386" ;;
		x86_64) architecture="amd64" ;;
		arm)    dpkg --print-architecture | grep -q "arm64" && architecture="arm64" || architecture="arm" ;;
	esac
	echo ${architecture}
}

# eks distro
install_kubectl() {
	local os="$1"
	local arch="$2"
	curl -L "https://distro.eks.amazonaws.com/kubernetes-1-19/releases/4/artifacts/kubernetes/v1.19.8/bin/${os}/${arch}/kubectl" -o /usr/local/bin/kubectl
	chmod +x /usr/local/bin/kubectl
}

# eksctl-anywhere
install_eksctl() {
	local os="$1"
	local arch="$2"
	# NOTE: temporarily using a local file uploaded with terraform
	#curl -L "URLNOTYETPROVIDED" -o /tmp/eksctl-anywhere.gz
	tar zxvf /tmp/eksctl-anywhere-${os}-${arch}.tar.gz -C /tmp/
	chmod +x /tmp/eksctl-anywhere
	mv /tmp/eksctl-anywhere /usr/local/bin/eksctl-anywhere
}

main() (
	local os
	local arch
	os="$(get_os)"
	arch="$(get_architecture)"
	if [ arch == "386" ]; then
		echo "unsupported processor architecture!"
		exit 1
	fi
	install_kubectl "${os}" "${arch}"
	install_eksctl "${os}" "${arch}"
)

main
