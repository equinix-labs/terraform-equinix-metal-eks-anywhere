#!/usr/bin/env bash
if [ "$1" == "" ]; then echo "Usage: $0 \"email\" [*taint|untaint|rm]"; exit 1; fi
module="${1}"
command=${2:-taint}

if [ "$command" == "rm" ]; then
	echo "NOTE: Make sure '$module' is removed from the CSV file!"
	command="state rm";
fi

# terraform state list | sed -E -e 's/\[/["/g' -e 's/\]/"]/g' -e 's/\["([0-9]+)"\]/[\1]/g' | 
terraform state list | grep "${module}" | while read resource; do terraform $command "${resource}"; done

echo Done! Run \"terraform apply\" when you are done marking instances to replace or remove.
