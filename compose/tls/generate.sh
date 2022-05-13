#!/usr/bin/env bash
set -euxo pipefail

csr=$(cat <<"EOF"
{
  "CN": "Tinkerbell",
  "hosts": [
    "TINKERBELL_HOST_IP",
    "tink-server.default.svc.cluster.local",
    "tink-server",
    "127.0.0.1",
    "localhost"
  ],
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "L": "@FACILITY@"
    }
  ]
}
EOF
)

ca_csr=$(cat <<"EOF"
{
  "CN": "Tinkerbell CA",
  "key": {
    "algo": "ecdsa",
    "size": 256
  },
  "names": [
    {
      "L": "@FACILITY@"
    }
  ]
}
EOF
)

ca_config=$(cat <<"EOF"
{
  "signing": {
    "default": {
      "expiry": "168h"
    },
    "profiles": {
      "server": {
        "expiry": "8760h",
        "usages": [
          "signing",
          "key encipherment",
          "server auth"
        ]
      },
      "signing": {
        "expiry": "8760h",
        "usages": [
          "signing",
          "key encipherment"
        ]
      }
    }
  }
}
EOF
)

write_csr() {
  echo "Writing file: $1"
  echo $csr | sed "s/TINKERBELL_HOST_IP/$2/g" > $1
}

write_ca_csr() {
  echo "Writing file: $1"
  echo $ca_csr > $1
}

write_ca_config() {
  echo "Writing file: $1"
  echo $ca_config > $1
}

# cleanup will remove unneeded files
cleanup() {
  rm -rf ca-key.pem ca.csr ca.pem server.csr server.pem
}

# gen will generate the key and certificate
gen() {
  local ca_crt_destination="$1"
  local server_crt_destination="$2"
  local server_key_destination="$3"
  local csr_file="$4"
  local ca_csr_file="$5"
  local ca_config_file="$6"

  cfssl gencert -initca "${ca_csr_file}" | cfssljson -bare ca -
  cfssl gencert -config "${ca_config_file}" -ca ca.pem -ca-key ca-key.pem -profile server "${csr_file}" | cfssljson -bare server
  mv ca.pem "${ca_crt_destination}"
  mv server.pem "${server_crt_destination}"
  mv server-key.pem "${server_key_destination}"
}

# main orchestrates the process
main() {
  local sans_ip="${TINKERBELL_HOST_IP}"
  local certs_dir="/certs/onprem"
  local csr_file="${certs_dir}/csr.json"
  local ca_csr_file="${certs_dir}/ca-csr.json"
  local ca_config_file="${certs_dir}/ca-config.json"
  local ca_crt_file="${certs_dir}/ca-crt.pem"
  local server_crt_file="${certs_dir}/server-crt.pem"
  local server_key_file="${certs_dir}/server-key.pem"
  # NB this is required for backward compat.
  # TODO once the other think-* services use server-crt.pem this should
  #      be removed.
  local bundle_crt_file="${certs_dir}/bundle.pem"

  # Writing the files required to generate certs
  write_csr "${csr_file}" "${sans_ip}"
  write_ca_csr "${ca_csr_file}"
  write_ca_config "${ca_config_file}"

  # Generate the certs
  gen "${ca_crt_file}" "${server_crt_file}" "${server_key_file}" "${csr_file}" "${ca_csr_file}" "${ca_config_file}"
  cp "${server_crt_file}" "${bundle_crt_file}"

  # Perform cleanup
  cleanup
}

main
