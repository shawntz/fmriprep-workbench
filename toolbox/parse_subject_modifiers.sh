#!/bin/bash
# @Author: Shawn Schwartz - Stanford Memory Lab
# @Date: December 17, 2025
# @Description: Parse subject ID with suffix modifiers from subject list files

# Maximum expected pipeline step number (adjust as pipeline steps are added)
readonly MAX_STEP_NUMBER=14
#
# This utility function parses subject IDs that may include suffix modifiers
# to provide granular control over pipeline execution.
#
# SUFFIX MODIFIER SYNTAX:
# subject_id:modifier1:modifier2:...
#
# SUPPORTED MODIFIERS:
# - step1, step2, step3, step4, step5, step6 : Only run specified step(s) for this subject
# - force : Force rerun even if subject was already processed
# - skip : Skip this subject entirely
#
# EXAMPLES:
# 101                    # Standard subject ID, no modifiers
# 102:step1              # Only run step 1 for subject 102
# 103:step1:step2        # Only run steps 1 and 2 for subject 103
# 104:force              # Force rerun for subject 104
# 105:step2:force        # Only run step 2, force rerun for subject 105
# 106:skip               # Skip subject 106 entirely
#
# USAGE:
# source ./toolbox/parse_subject_modifiers.sh
# parse_subject_modifiers "103:step1:force" "04-prep-fmriprep"
# 
# After calling parse_subject_modifiers, the following variables are set:
# - SUBJECT_ID: The base subject ID (e.g., "103")
# - SUBJECT_MODIFIERS: Array of modifiers (e.g., ("step1" "force"))
# - SHOULD_SKIP: "true" if subject should be skipped, "false" otherwise
# - SHOULD_FORCE: "true" if processing should be forced, "false" otherwise
# - SHOULD_RUN_STEP: "true" if current step should run for this subject, "false" otherwise

# Parse subject ID and modifiers from a subject list entry
# Args:
#   $1: subject_entry - The full subject entry from the list (e.g., "103:step1:force")
#   $2: current_step - The current pipeline step (e.g., "04-prep-fmriprep")
# Sets global variables: SUBJECT_ID, SUBJECT_MODIFIERS, SHOULD_SKIP, SHOULD_FORCE, SHOULD_RUN_STEP
parse_subject_modifiers() {
  local subject_entry="$1"
  local current_step="$2"
  
  # Initialize global variables
  SUBJECT_ID=""
  SUBJECT_MODIFIERS=()
  SHOULD_SKIP="false"
  SHOULD_FORCE="false"
  SHOULD_RUN_STEP="true"
  
  # Return empty if no entry provided
  if [ -z "${subject_entry}" ]; then
    return 1
  fi
  
  # Split the entry by colons
  IFS=':' read -ra PARTS <<< "${subject_entry}"
  
  # First part is always the subject ID
  SUBJECT_ID="${PARTS[0]}"
  
  # Trim whitespace from subject ID
  SUBJECT_ID=$(echo "${SUBJECT_ID}" | xargs)
  
  # If there's only one part, no modifiers present
  if [ ${#PARTS[@]} -eq 1 ]; then
    return 0
  fi
  
  # Collect all modifiers (everything after the first part)
  for (( i=1; i<${#PARTS[@]}; i++ )); do
    modifier=$(echo "${PARTS[$i]}" | xargs)  # trim whitespace
    if [ -n "${modifier}" ]; then
      SUBJECT_MODIFIERS+=("${modifier}")
    fi
  done
  
  # Process modifiers
  local has_step_modifier=false
  local step_number=""
  local current_step_found=false
  
  # Extract step number from current_step (e.g., "04-prep-fmriprep" -> "4")
  if [[ "${current_step}" =~ ^0*([0-9]+)- ]]; then
    step_number="${BASH_REMATCH[1]}"
  fi
  
  # First pass: check for skip, force, and step modifiers
  for modifier in "${SUBJECT_MODIFIERS[@]}"; do
    case "${modifier}" in
      skip)
        SHOULD_SKIP="true"
        SHOULD_RUN_STEP="false"
        return 0  # Skip overrides everything
        ;;
      force)
        SHOULD_FORCE="true"
        ;;
      step[1-9]|step[1-9][0-9]*)
        has_step_modifier=true
        # Extract the step number from modifier (e.g., "step1" -> "1")
        local modifier_step="${modifier#step}"
        # Warn if step number is out of expected range
        if [ "${modifier_step}" -gt "${MAX_STEP_NUMBER}" ]; then
          echo "($(date)) [WARNING] Step modifier 'step${modifier_step}' references a step that may not exist (expected: step1-step${MAX_STEP_NUMBER})" >&2
        fi
        # Check if this modifier matches the current step
        if [ "${modifier_step}" = "${step_number}" ]; then
          current_step_found=true
        fi
        ;;
      *)
        echo "($(date)) [WARNING] Unknown modifier '${modifier}' for subject ${SUBJECT_ID}" >&2
        ;;
    esac
  done
  
  # If step modifiers were specified, only run if current step was found
  if [ "${has_step_modifier}" = "true" ]; then
    if [ "${current_step_found}" = "true" ]; then
      SHOULD_RUN_STEP="true"
    else
      SHOULD_RUN_STEP="false"
    fi
  fi
  
  return 0
}

# Print parsed subject information (for debugging)
print_subject_info() {
  echo "Subject ID: ${SUBJECT_ID}"
  echo "Modifiers: ${SUBJECT_MODIFIERS[*]}"
  echo "Should Skip: ${SHOULD_SKIP}"
  echo "Should Force: ${SHOULD_FORCE}"
  echo "Should Run Step: ${SHOULD_RUN_STEP}"
}
