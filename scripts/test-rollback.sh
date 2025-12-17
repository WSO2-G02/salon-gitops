#!/bin/bash
# =============================================================================
# Rollback Test Script
# =============================================================================
# Tests the rollback functionality without actually rolling back
# Shows current versions and available rollback targets
#
# Usage:
#   ./test-rollback.sh              # Show all services
#   ./test-rollback.sh frontend     # Show specific service
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
AWS_REGION="us-east-1"
ECR_REGISTRY="024955634588.dkr.ecr.us-east-1.amazonaws.com"
GITOPS_DIR="$(cd "$(dirname "$0")/.." && pwd)"

SERVICES=("frontend" "user_service" "appointment_service" "service_management" "staff_management" "notification_service" "reports_analytics")

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}   Rollback Verification Tool${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Filter to specific service if provided
if [ -n "$1" ]; then
    SERVICES=("$1")
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    echo "Run: aws configure"
    exit 1
fi

echo -e "${CYAN}Checking current production versions...${NC}"
echo ""

echo "┌─────────────────────────┬────────────────────────────────┬────────────────────────────────┐"
echo "│ Service                 │ Current Production Tag         │ Previous Tag (Rollback)        │"
echo "├─────────────────────────┼────────────────────────────────┼────────────────────────────────┤"

for SERVICE in "${SERVICES[@]}"; do
    PROD_FILE="$GITOPS_DIR/production/${SERVICE}/deployment.yaml"
    
    if [ -f "$PROD_FILE" ]; then
        # Get current tag
        CURRENT_TAG=$(grep "image:" "$PROD_FILE" | head -1 | awk -F: '{print $NF}' | tr -d ' ')
        
        # Get previous tag from ECR
        PREVIOUS_TAG=$(aws ecr describe-images \
            --repository-name "$SERVICE" \
            --query 'sort_by(imageDetails,&imagePushedAt)[-2].imageTags[0]' \
            --output text 2>/dev/null || echo "N/A")
        
        # Format output
        printf "│ %-23s │ %-30s │ %-30s │\n" "$SERVICE" "${CURRENT_TAG:0:30}" "${PREVIOUS_TAG:0:30}"
    else
        printf "│ %-23s │ %-30s │ %-30s │\n" "$SERVICE" "FILE NOT FOUND" "-"
    fi
done

echo "└─────────────────────────┴────────────────────────────────┴────────────────────────────────┘"
echo ""

# Show staging vs production comparison
echo -e "${CYAN}Staging vs Production Comparison:${NC}"
echo ""
echo "┌─────────────────────────┬────────────────────────────────┬────────────────────────────────┐"
echo "│ Service                 │ Staging Tag                    │ Production Tag                 │"
echo "├─────────────────────────┼────────────────────────────────┼────────────────────────────────┤"

for SERVICE in "${SERVICES[@]}"; do
    STAGING_FILE="$GITOPS_DIR/staging/${SERVICE}/deployment.yaml"
    PROD_FILE="$GITOPS_DIR/production/${SERVICE}/deployment.yaml"
    
    STAGING_TAG="N/A"
    PROD_TAG="N/A"
    
    if [ -f "$STAGING_FILE" ]; then
        STAGING_TAG=$(grep "image:" "$STAGING_FILE" | head -1 | awk -F: '{print $NF}' | tr -d ' ')
    fi
    
    if [ -f "$PROD_FILE" ]; then
        PROD_TAG=$(grep "image:" "$PROD_FILE" | head -1 | awk -F: '{print $NF}' | tr -d ' ')
    fi
    
    # Check if they match (for backend, staging and prod use same tag)
    if [ "$STAGING_TAG" == "$PROD_TAG" ]; then
        STATUS="✓"
    else
        STATUS="≠"
    fi
    
    printf "│ %-23s │ %-30s │ %-30s │\n" "$SERVICE" "${STAGING_TAG:0:30}" "${PROD_TAG:0:30}"
done

echo "└─────────────────────────┴────────────────────────────────┴────────────────────────────────┘"
echo ""

# Show available tags in ECR for each service
echo -e "${CYAN}Available Tags in ECR (Last 5):${NC}"
echo ""

for SERVICE in "${SERVICES[@]}"; do
    echo -e "${YELLOW}$SERVICE:${NC}"
    aws ecr describe-images \
        --repository-name "$SERVICE" \
        --query 'sort_by(imageDetails,&imagePushedAt)[-5:].{Tag:imageTags[0],Pushed:imagePushedAt}' \
        --output table 2>/dev/null | tail -n +3 || echo "  No images found"
    echo ""
done

# Instructions
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Rollback Instructions${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "To rollback a service:"
echo ""
echo "  1. Go to GitHub Actions"
echo "  2. Select 'Rollback Production' workflow"
echo "  3. Choose service and type 'ROLLBACK'"
echo ""
echo "Or use GitHub CLI:"
echo ""
echo -e "  ${CYAN}gh workflow run rollback-production.yml \\${NC}"
echo -e "  ${CYAN}  --repo WSO2-G02/salon-gitops \\${NC}"
echo -e "  ${CYAN}  -f service=frontend \\${NC}"
echo -e "  ${CYAN}  -f rollback_type=previous \\${NC}"
echo -e "  ${CYAN}  -f confirm_rollback=ROLLBACK${NC}"
echo ""
