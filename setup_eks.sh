#!/usr/bin/env bash
set -xo pipefail

install_build_requirements() {
	apt install make
	snap install go --classic
}

# eksctl-anywhere
install_eksctl() {
	git clone https://github.com/aws/eks-anywhere
	cd eks-anywhere
	make eks-a
	mv bin/eksctl-anywhere /usr/local/bin
}

main() (
	install_build_requirements
	install_eksctl
)

main
