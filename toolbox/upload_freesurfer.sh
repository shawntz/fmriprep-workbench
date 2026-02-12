#!/bin/bash
# @Author: Shawn Schwartz - Stanford Memory Lab
# @Date: December 17, 2025
# @Description: Upload edited Freesurfer outputs back to server
# @Usage: ./upload_freesurfer.sh [options]

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Source configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKIP_SUBJECTS_PROMPT=true source "${SCRIPT_DIR}/../load_config.sh"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Freesurfer Edited Output Upload Utility                   ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Default values from config.yaml (fall back to hardcoded if not set)
REMOTE_SERVER="${FREESURFER_EDITING_REMOTE_SERVER:-}"
REMOTE_USER="${FREESURFER_EDITING_REMOTE_USER:-}"
REMOTE_BASE_DIR="${FREESURFER_EDITING_REMOTE_BASE_DIR:-}"
# Expand tilde in local directory path
LOCAL_FREESURFER_DIR="${FREESURFER_EDITING_LOCAL_FREESURFER_DIR:-${HOME}/freesurfer_edits}"
LOCAL_FREESURFER_DIR="${LOCAL_FREESURFER_DIR/#\~/$HOME}"
SUBJECTS_LIST="${FREESURFER_EDITING_SUBJECTS_LIST:-}"
UPLOAD_ALL="${FREESURFER_EDITING_UPLOAD_ALL:-false}"
BACKUP_ORIGINALS="${FREESURFER_EDITING_BACKUP_ORIGINALS:-true}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --server)
            REMOTE_SERVER="$2"
            shift 2
            ;;
        --user)
            REMOTE_USER="$2"
            shift 2
            ;;
        --remote-dir)
            REMOTE_BASE_DIR="$2"
            shift 2
            ;;
        --local-dir)
            LOCAL_FREESURFER_DIR="$2"
            shift 2
            ;;
        --subjects)
            SUBJECTS_LIST="$2"
            shift 2
            ;;
        --all)
            UPLOAD_ALL=true
            shift
            ;;
        --no-backup)
            BACKUP_ORIGINALS=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --server <hostname>        Remote server hostname (e.g., login.sherlock.stanford.edu)"
            echo "  --user <username>          Remote username"
            echo "  --remote-dir <path>        Remote base directory containing Freesurfer outputs"
            echo "  --local-dir <path>         Local directory with edited Freesurfer outputs (default: ~/freesurfer_edits)"
            echo "  --subjects <file|list>     Subject list file or comma-separated subject IDs"
            echo "  --all                      Upload all subjects in local directory"
            echo "  --no-backup                Don't create backup of original Freesurfer outputs on server"
            echo "  -h, --help                 Show this help message"
            echo ""
            echo "Interactive mode (no arguments):"
            echo "  Simply run without arguments to use interactive prompts"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Check if local directory exists
if [ ! -d "$LOCAL_FREESURFER_DIR" ]; then
    echo -e "${RED}Error: Local Freesurfer directory does not exist: ${LOCAL_FREESURFER_DIR}${NC}"
    echo -e "${YELLOW}Did you download Freesurfer outputs first with download_freesurfer.sh?${NC}"
    exit 1
fi

# Interactive mode if no arguments provided
if [ -z "$REMOTE_SERVER" ]; then
    echo -e "${YELLOW}Remote server hostname (e.g., login.sherlock.stanford.edu):${NC}"
    read -p "> " REMOTE_SERVER

    if [ -z "$REMOTE_SERVER" ]; then
        echo -e "${RED}Error: Server hostname is required${NC}"
        exit 1
    fi
fi

if [ -z "$REMOTE_USER" ]; then
    echo -e "${YELLOW}Remote username (SUNet ID):${NC}"
    read -p "> " REMOTE_USER

    if [ -z "$REMOTE_USER" ]; then
        echo -e "${RED}Error: Username is required${NC}"
        exit 1
    fi
fi

if [ -z "$REMOTE_BASE_DIR" ]; then
    echo -e "${YELLOW}Remote base directory (absolute path to BASE_DIR on server):${NC}"
    echo -e "${BLUE}(e.g., /oak/stanford/groups/yourlab/projects/yourstudy)${NC}"
    read -p "> " REMOTE_BASE_DIR

    if [ -z "$REMOTE_BASE_DIR" ]; then
        echo -e "${RED}Error: Remote base directory is required${NC}"
        exit 1
    fi
fi

# Construct remote Freesurfer directory path
REMOTE_FREESURFER_DIR="${REMOTE_BASE_DIR}/freesurfer"
# Escape path for safe use in remote shell
ESCAPED_REMOTE_FREESURFER_DIR=$(printf '%q' "$REMOTE_FREESURFER_DIR")

# Check if remote directory exists
echo ""
echo -e "${BLUE}Checking remote Freesurfer directory...${NC}"
if ! ssh "${REMOTE_USER}@${REMOTE_SERVER}" "[ -d '${ESCAPED_REMOTE_FREESURFER_DIR}' ]"; then
    echo -e "${RED}Error: Remote Freesurfer directory does not exist: ${REMOTE_FREESURFER_DIR}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Remote directory found${NC}"

# Get subjects list
if [ "$UPLOAD_ALL" = true ]; then
    echo ""
    echo -e "${BLUE}Finding all edited subjects locally...${NC}"
    SUBJECTS=$(ls -d ${LOCAL_FREESURFER_DIR}/sub-* 2>/dev/null | xargs -n 1 basename)

    if [ -z "$SUBJECTS" ]; then
        echo -e "${RED}Error: No subjects found in ${LOCAL_FREESURFER_DIR}${NC}"
        exit 1
    fi

    SUBJECT_COUNT=$(echo "$SUBJECTS" | wc -l)
    echo -e "${GREEN}Found ${SUBJECT_COUNT} edited subjects${NC}"
    echo ""
    echo "Subjects to upload:"
    echo "$SUBJECTS" | head -10
    if [ "$SUBJECT_COUNT" -gt 10 ]; then
        echo "... and $((SUBJECT_COUNT - 10)) more"
    fi

elif [ -z "$SUBJECTS_LIST" ]; then
    echo ""
    echo -e "${YELLOW}Enter subjects to upload:${NC}"
    echo -e "${BLUE}(Options: 'all', path to file, or comma-separated list like 'sub-001,sub-002')${NC}"
    read -p "> " SUBJECTS_INPUT

    if [ "$SUBJECTS_INPUT" = "all" ]; then
        SUBJECTS=$(ls -d ${LOCAL_FREESURFER_DIR}/sub-* 2>/dev/null | xargs -n 1 basename)
    elif [ -f "$SUBJECTS_INPUT" ]; then
        # Read from file, filter comments and blank lines
        SUBJECTS=$(grep -v '^[[:space:]]*#' "$SUBJECTS_INPUT" | grep -v '^[[:space:]]*$' | cut -d: -f1)
    else
        # Treat as comma-separated list
        SUBJECTS=$(echo "$SUBJECTS_INPUT" | tr ',' '\n')
    fi
else
    if [ -f "$SUBJECTS_LIST" ]; then
        SUBJECTS=$(grep -v '^[[:space:]]*#' "$SUBJECTS_LIST" | grep -v '^[[:space:]]*$' | cut -d: -f1)
    else
        SUBJECTS=$(echo "$SUBJECTS_LIST" | tr ',' '\n')
    fi
fi

# Ensure subjects have sub- prefix
SUBJECTS=$(echo "$SUBJECTS" | sed 's/^sub-//' | sed 's/^/sub-/')

# Verify subjects exist locally
echo ""
echo -e "${BLUE}Verifying local edited subjects...${NC}"
MISSING_SUBJECTS=""
VERIFIED_SUBJECTS=""

for subject in $SUBJECTS; do
    if [ -d "${LOCAL_FREESURFER_DIR}/${subject}" ]; then
        VERIFIED_SUBJECTS="${VERIFIED_SUBJECTS} ${subject}"
        echo -e "${GREEN}✓ ${subject}${NC}"
    else
        MISSING_SUBJECTS="${MISSING_SUBJECTS}\n  - ${subject}"
        echo -e "${RED}✗ ${subject} not found locally${NC}"
    fi
done

if [ -n "$MISSING_SUBJECTS" ]; then
    echo ""
    echo -e "${RED}Warning: Some subjects were not found locally:${MISSING_SUBJECTS}${NC}"
    read -p "Continue with available subjects? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Upload cancelled${NC}"
        exit 0
    fi
fi

SUBJECTS="$VERIFIED_SUBJECTS"

# Backup confirmation
echo ""
if [ "$BACKUP_ORIGINALS" = true ]; then
    echo -e "${YELLOW}Original Freesurfer outputs will be backed up on the server${NC}"
    echo -e "${BLUE}Backups will be created as: {subject}.backup.$(date +%Y%m%d_%H%M%S)${NC}"
else
    echo -e "${RED}Warning: --no-backup flag set - originals will be overwritten without backup${NC}"
    read -p "Are you sure you want to proceed without backups? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Upload cancelled. Remove --no-backup flag to create backups.${NC}"
        exit 0
    fi
fi

# Final confirmation
echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}IMPORTANT: You are about to upload edited Freesurfer outputs${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Local source:  ${LOCAL_FREESURFER_DIR}"
echo -e "  Remote target: ${REMOTE_USER}@${REMOTE_SERVER}:${REMOTE_FREESURFER_DIR}"
echo -e "  Subjects:      $(echo $SUBJECTS | wc -w) subjects"
echo -e "  Backup:        $([[ "$BACKUP_ORIGINALS" = true ]] && echo 'Yes' || echo 'No')"
echo ""
echo -e "${RED}This will replace existing Freesurfer outputs on the server!${NC}"
echo -e "${BLUE}Future fMRIPrep runs will use these edited surfaces.${NC}"
echo ""
read -p "Are you absolutely sure you want to proceed? (type 'yes' to confirm) " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}Upload cancelled${NC}"
    exit 0
fi

# Upload subjects
echo ""
echo -e "${GREEN}Starting upload...${NC}"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_SUBJECTS=""
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

for subject in $SUBJECTS; do
    echo -e "${BLUE}Uploading ${subject}...${NC}"

    # Create backup on server if requested
    if [ "$BACKUP_ORIGINALS" = true ]; then
        echo "  Creating backup of original..."
        # Escape variables for safe remote execution
        ESCAPED_REMOTE_DIR=$(printf '%q' "$REMOTE_FREESURFER_DIR")
        ESCAPED_SUBJECT=$(printf '%q' "$subject")
        ESCAPED_TIMESTAMP=$(printf '%q' "$BACKUP_TIMESTAMP")
        if ssh "${REMOTE_USER}@${REMOTE_SERVER}" "
            if [ -d ${ESCAPED_REMOTE_DIR}/${ESCAPED_SUBJECT} ]; then
                cp -r ${ESCAPED_REMOTE_DIR}/${ESCAPED_SUBJECT} ${ESCAPED_REMOTE_DIR}/${ESCAPED_SUBJECT}.backup.${ESCAPED_TIMESTAMP}
                echo '  ✓ Backup created'
            else
                echo '  ℹ No existing directory to backup'
            fi
        "; then
            echo -e "${GREEN}  ✓ Backup completed${NC}"
        else
            echo -e "${YELLOW}  ! Backup failed, but continuing...${NC}"
        fi
    fi

    # Upload edited Freesurfer directory using rsync
    echo "  Uploading edited surfaces..."
    if rsync -avz --progress \
        "${LOCAL_FREESURFER_DIR}/${subject}/" \
        "${REMOTE_USER}@${REMOTE_SERVER}:'${REMOTE_FREESURFER_DIR}/${subject}/'"; then

        echo -e "${GREEN}✓ ${subject} uploaded successfully${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗ Failed to upload ${subject}${NC}"
        FAILED_SUBJECTS="${FAILED_SUBJECTS}\n  - ${subject}"
        ((FAIL_COUNT++))
    fi
    echo ""
done

# Summary
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                     Upload Summary                             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Successfully uploaded: ${SUCCESS_COUNT} subjects${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}Failed to upload: ${FAIL_COUNT} subjects${NC}"
    echo -e "${RED}Failed subjects:${FAILED_SUBJECTS}${NC}"
fi
echo ""
if [ "$BACKUP_ORIGINALS" = true ]; then
    echo -e "${BLUE}Original Freesurfer outputs backed up on server as:${NC}"
    echo -e "  {subject}.backup.${BACKUP_TIMESTAMP}"
    echo ""
fi
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Run fMRIPrep step 9 (full workflows) to use edited surfaces"
echo "   ./09-run.sbatch"
echo ""
echo "2. fMRIPrep will automatically use the edited Freesurfer outputs"
echo "   instead of rerunning Freesurfer reconstruction"
echo ""
echo -e "${BLUE}Note: To revert to original surfaces (if backups were created):${NC}"
shown_count=0
for subject in $SUBJECTS; do
    if [ "$BACKUP_ORIGINALS" = true ]; then
        echo "  ssh ${REMOTE_USER}@${REMOTE_SERVER} \"rm -rf ${REMOTE_FREESURFER_DIR}/${subject} && mv ${REMOTE_FREESURFER_DIR}/${subject}.backup.${BACKUP_TIMESTAMP} ${REMOTE_FREESURFER_DIR}/${subject}\""
        shown_count=$((shown_count + 1))
        if [ "$shown_count" -ge 3 ]; then
            break
        fi
    fi
done
if [ $(echo $SUBJECTS | wc -w) -gt 3 ]; then
    echo "  ... (and similar for other subjects)"
fi
echo ""
echo -e "${GREEN}Upload complete!${NC}"
