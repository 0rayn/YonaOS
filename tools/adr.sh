#!/usr/bin/env bash
# YonaOS ADR Management Tool

ADR_DIR="Documentation/ADR"
mkdir -p "$ADR_DIR"

DATE=$(date +"%Y-%m-%d")
AUTHOR=$(git config user.name || echo "YonaOS Contributor")

get_next_id() {
    local highest=$(ls -1 "$ADR_DIR" 2>/dev/null | grep -Eo '^[0-9]{4}' | sort -n | tail -1)
    if [ -z "$highest" ]; then
        echo "0001"
    else
        printf "%04d\n" $((10#$highest + 1))
    fi
}

format_filename() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-|-$//g'
}

generate_template() {
    local id=$1
    local title=$2
    local filepath=$3
    local old_ref=$4

    cat <<EOF > "$filepath"
# ADR ${id}: ${title}

## Metadata
* **Date:** ${DATE}
* **Author:** ${AUTHOR}
* **Approved-by**: -
* **Status:** Pending
${old_ref}

## 1. Context
[Explain the technical context and the problem being solved...]

## 2. Decision
[State the exact architecture or tooling decision...]

## 3. Alternatives Considered
* **[Alternative 1]:** [Why it was rejected]

## 4. Rationale
[Explain why the chosen decision is the best fit for YonaOS...]

## 5. Consequences
* **Positive:** [What gets better, faster, or safer]
* **Negative:** [What tech debt or friction is assumed]
EOF
}

# ---------------------------------------------------------
# COMMAND: new
# ---------------------------------------------------------
if [ "$1" == "new" ]; then
    if [ -z "$2" ]; then
        echo "Error: Title required. Usage: ./tools/adr.sh new \"Title\""
        exit 1
    fi

    TITLE="$2"
    ID=$(get_next_id)
    FILENAME="${ID}-$(format_filename "$TITLE").md"
    FILEPATH="${ADR_DIR}/${FILENAME}"

    generate_template "$ID" "$TITLE" "$FILEPATH" ""
    echo "Success: Created new ADR -> $FILEPATH"
    exit 0
fi

# ---------------------------------------------------------
# COMMAND: approve
# ---------------------------------------------------------
if [ "$1" == "approve" ]; then
    if [ -z "$2" ]; then
        echo "Usage: ./tools/adr.sh approve <ID>"
        echo "Example: ./tools/adr.sh approve 1"
        exit 1
    fi

    APPROVE_ID=$(printf "%04d" "$2")
    
    # Find the target file
    ADR_FILE=$(ls -1 "$ADR_DIR" 2>/dev/null | grep "^${APPROVE_ID}-")
    if [ -z "$ADR_FILE" ]; then
        echo "Error: Could not find ADR starting with ${APPROVE_ID}"
        exit 1
    fi

    FILEPATH="${ADR_DIR}/${ADR_FILE}"

    # Swap Pending to Accepted and add the signing author
    sed -i 's/\* \*\*Status:\*\* Pending/\* \*\*Status:\*\* Accepted/' "$FILEPATH"
    sed -i "s/\* \*\*Approved-by\*\*: -/\* \*\*Approved-by\*\*: ${AUTHOR}/" "$FILEPATH"

    echo "Success: Approved ADR ${APPROVE_ID} -> ${ADR_FILE}"
    exit 0
fi

# ---------------------------------------------------------
# COMMAND: supersede
# ---------------------------------------------------------
if [ "$1" == "supersede" ]; then
    if [ -z "$2" ] || [ -z "$3" ]; then
        echo "Usage: ./tools/adr.sh supersede <OLD_ID> \"New Title\""
        echo "Example: ./tools/adr.sh supersede 3 \"Drop QEMU for Bochs\""
        exit 1
    fi

    OLD_ID=$(printf "%04d" "$2")
    TITLE="$3"
    
    # Find the old file
    OLD_FILE=$(ls -1 "$ADR_DIR" 2>/dev/null | grep "^${OLD_ID}-")
    if [ -z "$OLD_FILE" ]; then
        echo "Error: Could not find ADR starting with ${OLD_ID}"
        exit 1
    fi

    # Create the new file
    NEW_ID=$(get_next_id)
    NEW_FILENAME="${NEW_ID}-$(format_filename "$TITLE").md"
    NEW_FILEPATH="${ADR_DIR}/${NEW_FILENAME}"
    
    # Add a reference in the new file pointing back to the old one
    OLD_REF="* **Supersedes:** [ADR ${OLD_ID}](${OLD_FILE})"
    generate_template "$NEW_ID" "$TITLE" "$NEW_FILEPATH" "$OLD_REF"

    # Modify the old file to mark it as deprecated
    OLD_FILEPATH="${ADR_DIR}/${OLD_FILE}"
    
    # Change whatever current status it has (Pending or Accepted) to Deprecated
    sed -i 's/\* \*\*Status:\*\* .*/\* \*\*Status:\*\* Deprecated/' "$OLD_FILEPATH"
    
    # Insert the deprecation warning right below the main title (Line 2)
    WARNING_TEXT="\n> **WARNING: This decision is DEPRECATED in favor of [ADR ${NEW_ID}](${NEW_FILENAME})**\n"
    sed -i "2i\\$WARNING_TEXT" "$OLD_FILEPATH"

    echo "Success: Created $NEW_FILENAME"
    echo "Success: Deprecated $OLD_FILE"
    exit 0
fi


# ---------------------------------------------------------
# COMMAND: list
# ---------------------------------------------------------
if [ "$1" == "list" ]; then
    # Print a clean, formatted header table
    printf "%-6s %-40s %-20s %-20s\n" "ID" "TITLE" "STATUS" "AUTHOR"
    echo "----------------------------------------------------------------------------------------"
    
    for file in "$ADR_DIR"/*.md; do
        [ -e "$file" ] || continue
        
        ID=$(basename "$file" | cut -d'-' -f1)
        STATUS=$(grep -m 1 "Status:" "$file" | awk -F': ' '{print $2}')
        AUTHOR=$(grep -m 1 "Author:" "$file" | awk -F': ' '{print $2}')
        TITLE=$(grep -m 1 "^# ADR" "$file" | cut -d':' -f2- | sed 's/^ //')
        
        # Max out title display length to prevent table breaking on huge titles
        if [ ${#TITLE} -gt 38 ]; then
            TITLE="${TITLE:0:35}..."
        fi

        # Colorize status for clear visual tracking
        if [ "$STATUS" == "Accepted" ]; then
            STATUS_COL="\033[32m$STATUS\033[0m"      # Green
        elif [ "$STATUS" == "Pending" ]; then
            STATUS_COL="\033[33m$STATUS\033[0m"       # Yellow
        else
            STATUS_COL="\033[31m$STATUS\033[0m"       # Red (Deprecated)
        fi
        
        # Format columns dynamically (-40 ensures text aligns nicely to the left)
        printf "%-6s %-40s %-30s %-20s\n" "${ID}" "${TITLE}" "${STATUS_COL}" "${AUTHOR}"
    done
    exit 0
fi

# Print help
echo "YonaOS ADR Tool"
echo "Usage:"
echo "  ./tools/adr.sh new \"Title\"               - Create a new pending decision"
echo "  ./tools/adr.sh approve <ID>              - Approve a pending decision"
echo "  ./tools/adr.sh supersede <ID> \"Title\"    - Replace an old decision"
echo "  ./tools/adr.sh list                      - Show all decisions"
exit 1
