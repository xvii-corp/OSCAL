#!/bin/bash

if [ -z ${OSCAL_SCRIPT_INIT+x} ]; then
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)/include/init-oscal.sh"
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)/../metaschema/scripts/include/init-saxon.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)/../metaschema/scripts/include/init-validate-content.sh"

# configuration
UNIT_TESTS_DIR="$(get_abs_path "${OSCALDIR}/src/specifications/profile-resolution/profile-resolution-examples")"
EXPECTED_DIR="$(get_abs_path "${OSCALDIR}/src/specifications/profile-resolution/profile-resolution-examples/output-expected")"
PROFILE_RESOLVER="$(get_abs_path "${OSCALDIR}/src/utils/util/resolver-pipeline/oscal-profile-RESOLVE.xsl")"
CATALOG_SCHEMA="$(get_abs_path "${OSCALDIR}/xml/schema/oscal_catalog_schema.xsd")"

# Option defaults
KEEP_TEMP_SCRATCH_DIR=false

usage() {                                      # Function: Print a help message.
  cat << EOF
Usage: $0 [options] [metaschema paths]

-h, --help                        Display help
--scratch-dir DIR                 Generate temporary artifacts in DIR
                                  If not provided a new directory will be
                                  created under \$TMPDIR if set or in /tmp.
--keep-temp-scratch-dir           If a scratch directory is automatically
                                  created, it will not be automatically removed.
-v                                Provide verbose output
EOF
}


OPTS=`getopt -o w:vh --long scratch-dir:,keep-temp-scratch-dir,help -n "$0" -- "$@"`
if [ $? != 0 ] ; then echo -e "Failed parsing options." >&2 ; usage ; exit 1 ; fi

# Process arguments
eval set -- "$OPTS"
while [ $# -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --scratch-dir)
      SCRATCH_DIR="$(realpath "$2")"
      shift # past unit_test_dir
      ;;
    --keep-temp-scratch-dir)
      KEEP_TEMP_SCRATCH_DIR=true
      ;;
    -v)
      VERBOSE=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --) # end of options
      shift
      break;
      ;;
    *)    # unknown option
      echo "Unhandled option: $1"
      exit 1
      ;;
  esac
  shift # past argument
done

OTHER_ARGS=$@ # save the remaining args

if [ -z "${SCRATCH_DIR+x}" ]; then
  SCRATCH_DIR="$(mktemp -d)"
  if [ "$KEEP_TEMP_SCRATCH_DIR" != "true" ]; then
    function CleanupScratchDir() {
      rc=$?
      if [ "$VERBOSE" = "true" ]; then
        echo -e ""
        echo -e "${P_INFO}Cleanup${P_END}"
        echo -e "${P_INFO}=======${P_END}"
        echo -e "${P_INFO}Deleting scratch directory:${P_END} ${SCRATCH_DIR}"
      fi
      rm -rf "${SCRATCH_DIR}"
      exit $rc
    }
    trap CleanupScratchDir EXIT
  fi
fi

echo -e ""
echo -e "${P_INFO}Testing Profile Resolution${P_END}"
echo -e "${P_INFO}==============================${P_END}"

if [ "$VERBOSE" = "true" ]; then
  echo -e "${P_INFO}Using working directory:${P_END} ${WORKING_DIR}"
fi

test_files=()
while read -r -d $'\0' file; do
  test_files+=("$file")
done < <(find "$UNIT_TESTS_DIR" -mindepth 1 -maxdepth 1 -type f -name "*_profile.xml" -print0)

unit_test_scratch_dir="$SCRATCH_DIR/profile-resolution"
mkdir -p "$unit_test_scratch_dir"


for file in ${test_files[@]}; do
  filename="$(basename -- "$file")"
  extension="${filename##*.}"
  filename_minus_extension="${filename%.*}"
  echo "${extension}"
  echo "${filename_minus_extension}"

  resolved_profile="${unit_test_scratch_dir}/${filename_minus_extension}_RESOLVED.${extension}"
  echo "${resolved_profile}"
  
  result=$(xsl_transform "${PROFILE_RESOLVER}" "$file" "${resolved_profile}" 2>&1)
  cmd_exitcode=$?
  if [ $cmd_exitcode -ne 0 ]; then
    echo -e "  ${P_ERROR}Failed to resolve profile '${P_END}${filename}${P_ERROR}'.${P_END}"
    exitcode=1
    continue;
  fi
  
  result=$(validate_xml "$CATALOG_SCHEMA" "${resolved_profile}")
  if [ $cmd_exitcode -ne 0 ]; then
    echo -e "  ${P_ERROR}Resolved profile '${P_END}${filename}${P_ERROR}' is not a valid OSCAL catalog.${P_END}"
    exitcode=1
    continue;
  fi

  expected_resolved_profile="${EXPECTED_DIR}/${filename_minus_extension}_RESOLVED.${extension}"

  result=$(diff "${resolved_profile}" "${expected_resolved_profile}")
  if [ $cmd_exitcode -ne 0 ]; then
    echo -e "  ${P_ERROR}Resolved profile '${P_END}${filename}${P_ERROR}' does not match the expected resolved profile.${P_END}"
    exitcode=1
    continue;
  fi
done


exit 1

exitcode=0
for i in ${!paths[@]}; do
  metaschema="${paths[$i]}"
  gen_schema="${formats[$i]}"

  filename=$(basename -- "$metaschema")
  extension="${filename##*.}"
  filename="${filename%.*}"
  base="${filename/_metaschema/}"
  metaschema_relative=$(get_rel_path "${OSCALDIR}" "${metaschema}")

  #split on commas
  IFS_OLD="$IFS"
  IFS=, gen_formats=($gen_schema)
  IFS="$IFS_OLD"
  for format in ${gen_formats[@]}; do
    if [ -z "$format" ]; then
      # skip blanks
      continue;
    fi

    case $format in
    xml)
      generator_arg="--xml"
      schema="$WORKING_DIR/$format/schema/${base}_schema.xsd"
      ;;
    json)
      generator_arg="--json"
      schema="$WORKING_DIR/$format/schema/${base}_schema.json"
      ;;
    *)
      echo -e "${P_WARN}Unsupported schema format '${format^^}' schema for '$metaschema'.${P_END}"
      continue;
      ;;
    esac

    # ensure the schema directory exists before calling realpath
    mkdir -p "$(dirname "$schema")"
    schema_relative=$(get_rel_path "${WORKING_DIR}" "${schema}")

    if [ "$VERBOSE" == "true" ]; then
      echo -e "${P_INFO}Generating ${format^^} schema for '${P_END}${metaschema_relative}${P_INFO}' as '${P_END}${schema_relative}${P_INFO}'.${P_END}"
    fi

    args=()
    args+=("${generator_arg}")
    args+=("$metaschema")
    args+=("$schema")
    args+=("--validate")

    if [ "$VERBOSE" == "true" ]; then
      args+=("-v")
    fi    

    result=$("$OSCALDIR/build/metaschema/scripts/generate-schema.sh" "${args[@]}" 2>&1)
    cmd_exitcode=$?
    if [ $cmd_exitcode -ne 0 ]; then
      echo -e "${P_ERROR}Generation of ${format^^} schema failed for '${P_END}${metaschema_relative}${P_ERROR}'.${P_END}"
      echo -e "${P_ERROR}${result}${P_END}"
      exitcode=1
    else
      echo -e "${result}"
      if [ "$VERBOSE" == "true" ]; then
        echo -e "${P_OK}Generation of ${format^^} schema passed for '${P_END}${metaschema_relative}${P_OK}'.${P_END}"
      fi
    fi
  done
done

exit $exitcode
