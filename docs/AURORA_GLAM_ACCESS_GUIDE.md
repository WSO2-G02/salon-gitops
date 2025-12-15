# 💅 Aurora Glam - Salon Booking System

## 🌐 Website Access Links

### Main Website
| Environment | URL | Purpose |
|-------------|-----|---------|
| **Production** | https://aurora-glam.com | Main website for customers |
| **Staging** | https://staging.aurora-glam.com *(if configured)* | Testing environment |

---

## 👥 User Roles & Access

### 1. Customer Access
**URL:** https://aurora-glam.com

**Features:**
- Browse salon services
- Book appointments
- View booking history
- Manage profile
- Receive notifications

**How to Register:**
1. Go to https://aurora-glam.com
2. Click "Sign Up" or "Register"
3. Fill in your details (email, name, phone)
4. Verify your email
5. Start booking!

---

### 2. Staff/Stylist Access
**URL:** https://aurora-glam.com/staff *(or staff login page)*

**Features:**
- View assigned appointments
- Manage availability/schedule
- Update appointment status
- View customer information

---

### 3. Admin/Manager Access
**URL:** https://aurora-glam.com/admin

**Features:**
- Manage all services
- Manage staff members
- View analytics & reports
- Configure business settings
- Handle customer management

---

## 📱 API Endpoints (For Developers)

| Service | Base URL | Health Check |
|---------|----------|--------------|
| User Service | `https://aurora-glam.com/api/users` | `/api/v1/health` |
| Service Management | `https://aurora-glam.com/api/services` | `/api/v1/health` |
| Staff Management | `https://aurora-glam.com/api/staff` | `/api/v1/health` |
| Appointments | `https://aurora-glam.com/api/appointments` | `/api/v1/health` |
| Notifications | `https://aurora-glam.com/api/notifications` | `/api/v1/notifications/health` |
| Reports & Analytics | `https://aurora-glam.com/api/reports` | `/api/v1/health` |

**Example API Calls:**
```bash
# Check user service health
curl https://aurora-glam.com/api/users/api/v1/health

# Login
curl -X POST https://aurora-glam.com/api/users/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "yourpassword"}'

# Get services list (public)
curl https://aurora-glam.com/api/services/api/v1/services
```

---

## 🔧 For Developers/Team Members

### GitHub Repositories
| Repository | Purpose |
|------------|---------|
| `WSO2-G02/salon-booking-frontend-dev` | Next.js frontend application |
| `WSO2-G02/salon-booking-backend-dev` | Python FastAPI microservices |
| `WSO2-G02/salon-gitops` | Kubernetes manifests & ArgoCD apps |
| `WSO2-G02/salon-k8s-infra` | Terraform infrastructure code |

### ArgoCD Dashboard
**URL:** https://argocd.aurora-glam.com *(or port-forward)*

```bash
# Port forward to access ArgoCD locally
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Access at: https://localhost:8080
```

### Monitoring & Observability
- **Kiali (Service Mesh):** Port-forward to Kiali
- **Grafana (Metrics):** Port-forward to Grafana
- **Jaeger (Tracing):** Port-forward to Jaeger

---

## 🆘 Troubleshooting

### Website Not Loading?
1. Check if DNS is resolving: `nslookup aurora-glam.com`
2. Check SSL certificate: Visit https://aurora-glam.com and check certificate

### API Errors?
1. Check health endpoints first
2. Look at browser console for CORS errors
3. Contact the dev team with error details

### Need Access to Admin Panel?
Contact the system administrator for admin credentials.

---

## 📧 Contact & Support

For technical issues or access requests, contact the development team.

---

*Last Updated: December 15, 2025*
