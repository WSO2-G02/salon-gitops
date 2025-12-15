# GitHub Secrets Configuration Guide

> **Date**: December 15, 2025  
> **Purpose**: Configure frontend repository secrets for aurora-glam.com domain

---

## Overview

The frontend uses `NEXT_PUBLIC_*` environment variables that are baked into the Docker image at build time via GitHub Actions CI/CD. These variables tell the browser where to make API calls.

## Architecture Flow

```
User's Browser
    │
    │  JavaScript fetch("https://aurora-glam.com/api/users/api/v1/login")
    │  (NEXT_PUBLIC_USER_API_BASE = https://aurora-glam.com/api/users)
    ▼
AWS ALB (HTTPS via ACM Certificate)
    │
    ▼
Istio Gateway (salon-gateway)
    │
    ▼
VirtualService (salon-routes)
    │  Strips /api/users/ prefix → /api/v1/login
    ▼
Kubernetes Service: user-service:80
    │
    ▼
Backend Pod (FastAPI)
    │  Receives: /api/v1/login ✓
    └─ Returns JSON response
```

---

## Required GitHub Secrets

Navigate to:
**GitHub** → **WSO2-G02/salon-booking-frontend-dev** → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add the following secrets:

### 1. User Service
```
Name:  NEXT_PUBLIC_USER_API_BASE
Value: https://aurora-glam.com/api/users
```

### 2. Service Management
```
Name:  NEXT_PUBLIC_SERVICE_API_BASE
Value: https://aurora-glam.com/api/services
```

### 3. Staff Management
```
Name:  NEXT_PUBLIC_STAFF_API_BASE
Value: https://aurora-glam.com/api/staff
```

### 4. Appointment Service
```
Name:  NEXT_PUBLIC_APPOINTMENT_API_BASE
Value: https://aurora-glam.com/api/appointments
```

### 5. Notification Service
```
Name:  NEXT_PUBLIC_NOTIFICATION_API_BASE
Value: https://aurora-glam.com/api/notifications
```

### 6. Analytics Service
```
Name:  NEXT_PUBLIC_ANALYTICS_API_BASE
Value: https://aurora-glam.com/api/reports
```

---

## How It Works

### Example: User Login

**Frontend Code** (src/services/userService.ts):
```typescript
const API_BASE = process.env.NEXT_PUBLIC_USER_API_BASE;

export async function loginUser(data) {
  const res = await fetch(`${API_BASE}/api/v1/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  return await res.json()
}
```

**At Build Time** (GitHub Actions CI/CD):
```bash
# GitHub Actions reads secret
NEXT_PUBLIC_USER_API_BASE=https://aurora-glam.com/api/users

# Passes to Docker build
docker build --build-arg NEXT_PUBLIC_USER_API_BASE=https://aurora-glam.com/api/users

# Baked into Next.js bundle
# Browser will call: https://aurora-glam.com/api/users/api/v1/login
```

**At Runtime** (Browser):
```javascript
// JavaScript executes:
fetch("https://aurora-glam.com/api/users/api/v1/login", {
  method: 'POST',
  body: JSON.stringify({username: 'user', password: 'pass'})
})
```

**Routing** (Istio VirtualService):
```yaml
# Matches: /api/users/
# Rewrites to: / (strips prefix)
# Result: /api/users/api/v1/login → /api/v1/login
# Forwards to: user-service:80
```

**Backend** (FastAPI receives):
```python
@router.post("/api/v1/login")
async def login(data: LoginRequest):
    # Receives the request ✓
    return {"access_token": "...", "token_type": "bearer"}
```

---

## After Adding Secrets

### Trigger Frontend Rebuild

1. **Manual Trigger**:
   - Go to **Actions** → **Frontend CI/CD** → **Run workflow**
   - Click "Run workflow" button

2. **Or push a commit**:
   ```bash
   cd salon-booking-frontend-dev
   git commit --allow-empty -m "chore: trigger rebuild with new secrets"
   git push origin main
   ```

3. **Monitor the build**:
   - GitHub Actions will build new Docker image
   - Push to ECR with new tag
   - Update GitOps repo
   - ArgoCD will deploy automatically

### Verify Deployment

After ~5-10 minutes:

```bash
# Check ArgoCD sync status
kubectl get applications -n argocd | grep frontend

# Check pod is running with new image
kubectl get pods -n staging -l app=frontend

# Get the image tag
kubectl get deployment frontend -n staging -o jsonpath='{.spec.template.spec.containers[0].image}'

# Test API call from browser DevTools Console:
# Open https://aurora-glam.com
# Press F12 → Console tab
# Run:
fetch('https://aurora-glam.com/api/users/api/v1/health')
  .then(r => r.json())
  .then(console.log)
```

Expected output:
```json
{
  "status": "healthy",
  "service": "user_service",
  "database": "connected"
}
```

---

## Troubleshooting

### Issue: 404 Errors on API Calls

**Check 1: Secrets are configured**
- Verify all 6 secrets exist in GitHub repository settings

**Check 2: Frontend was rebuilt**
- Check GitHub Actions logs to confirm build used the secrets
- Look for: `ENV NEXT_PUBLIC_USER_API_BASE=https://aurora-glam.com/api/users`

**Check 3: VirtualService routing**
```bash
kubectl get vs salon-routes -n staging -o yaml | grep -A5 "prefix: /api/users"
```

Should show:
```yaml
- match:
  - uri:
      prefix: /api/users/
  rewrite:
    uri: /
```

**Check 4: Test routing manually**
```bash
curl -s https://aurora-glam.com/api/users/api/v1/health
```

### Issue: CORS Errors

**Browser Console shows**: `Access to fetch at 'https://aurora-glam.com/api/users/...' from origin 'https://aurora-glam.com' has been blocked by CORS`

**Solution**: Backend CORS settings need to include the domain:
```python
# user_service/app/config.py
ALLOWED_ORIGINS = [
    "http://localhost:3000",
    "https://aurora-glam.com"  # Add this
]
```

---

## Security Notes

### Why NEXT_PUBLIC_ Variables Are Not Secret

⚠️ **Important**: Any variable prefixed with `NEXT_PUBLIC_` is **exposed to the browser**. This means:

- Anyone can see these URLs by viewing browser DevTools → Network tab
- They should only contain **public information** (API endpoints)
- **NEVER** put credentials, API keys, or tokens in `NEXT_PUBLIC_` variables

### What IS Secret

✅ **These remain secure**:
- Database passwords (in Kubernetes Secrets)
- JWT secret keys (in Kubernetes Secrets)
- SMTP passwords (in Kubernetes Secrets)
- AWS credentials (in GitHub Secrets, used by CI/CD only)

The API endpoints themselves are public (anyone can try to call them), but:
- Authentication is required for protected endpoints
- Rate limiting prevents abuse
- Istio provides network security within the cluster

---

## Related Documentation

- [Secrets and Database Setup](./SECRETS_AND_DATABASE_SETUP.md)
- [Frontend CI/CD Workflow](../../salon-booking-frontend-dev/.github/workflows/ci-cd.yml)
- [VirtualService Routes](../staging/salon-routes.yaml)

---

## Change Log

| Date | Change | Author |
|------|--------|--------|
| 2025-12-15 | Initial documentation created | DevOps |
| 2025-12-15 | Fixed VirtualService path rewriting | DevOps |
| 2025-12-15 | Configured domain aurora-glam.com | DevOps |
