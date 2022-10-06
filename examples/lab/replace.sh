#!/usr/bin/env bash
if [ "$1" == "" ]; then echo "Usage: $0 \"email\" [*taint|untaint|rm] [admin|cp|dp|addon]"; exit 1; fi
module="${1}"
command=${2:-taint}
resources="${3}"

if [ "$command" == "rm" ]; then
	echo "Remove ${resources} resources for '$1' from Terraform state? You may also want to update the CSV file and manually delete the resources (or not). Proceed with caution."

	read -p "Remove? [y|n] " yn
	case $yn in
		[Yy]*) command="state rm";;
		*) exit;;
	esac

fi

# terraform state list | sed -E -e 's/\[/["/g' -e 's/\]/"]/g' -e 's/\["([0-9]+)"\]/[\1]/g' | 
terraform state list | grep "${module}" | grep -E -e "${resources}" | while read resource; do terraform $command "${resource}"; done

echo Done! Run \"terraform apply\" when you are done marking instances to replace or remove.
