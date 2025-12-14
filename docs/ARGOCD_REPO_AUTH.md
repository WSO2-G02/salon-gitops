# ArgoCD Repository Authentication Setup

The ArgoCD applications are failing to sync because the repository `https://github.com/WSO2-G02/salon-gitops` is private and ArgoCD doesn't have credentials configured.

## Fix ArgoCD Repository Credentials

### Option 1: Using GitHub Personal Access Token (PAT)

1. **Generate a GitHub PAT:**
   - Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Generate new token with `repo` scope
   - Copy the token

2. **Create Secret via kubectl:**
   Connect to the cluster (via EC2 Instance Connect or local kubectl) and run:

   ```bash
   kubectl create secret generic argocd-repo-creds \
     --namespace argocd \
     --from-literal=type=git \
     --from-literal=url=https://github.com/WSO2-G02/salon-gitops \
     --from-literal=username=<YOUR_GITHUB_USERNAME> \
     --from-literal=password=<YOUR_GITHUB_PAT_TOKEN>
   
   kubectl label secret argocd-repo-creds -n argocd argocd.argoproj.io/secret-type=repository
   ```

3. **Verify the secret:**
   ```bash
   kubectl get secret argocd-repo-creds -n argocd -o yaml
   ```

### Option 2: Using ArgoCD CLI

1. **Get ArgoCD admin password:**
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

2. **Login to ArgoCD:**
   ```bash
   argocd login argocd.aurora-glam.com --username admin --password <password> --insecure
   ```

3. **Add repository credentials:**
   ```bash
   argocd repo add https://github.com/WSO2-G02/salon-gitops \
     --username <YOUR_GITHUB_USERNAME> \
     --password <YOUR_GITHUB_PAT_TOKEN>
   ```

### Option 3: Using ArgoCD Web UI

1. **Access ArgoCD:** http://argocd.aurora-glam.com

2. **Get admin password:**
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   ```

3. **Login:** Username: `admin`, Password: (from above)

4. **Add Repository:**
   - Go to Settings → Repositories → Connect Repo
   - Connection Method: VIA HTTPS
   - Type: git
   - Project: default
   - Repository URL: https://github.com/WSO2-G02/salon-gitops
   - Username: Your GitHub username
   - Password: Your GitHub PAT token

## After Adding Credentials

Once credentials are configured, refresh the applications:

```bash
# Refresh all applications
for app in $(kubectl get applications -n argocd -o name); do
  kubectl patch $app -n argocd --type=merge -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {}}}'
done

# Or refresh individual application
argocd app get <app-name> --refresh
```

## Verify Sync Status

```bash
kubectl get applications -n argocd
```

Expected output after fix:
```
NAME                         SYNC STATUS   HEALTH STATUS
appointment-service          Synced        Healthy
frontend                     Synced        Healthy
...
```

## Alternative: Make Repository Public

If the repository can be made public:
1. Go to GitHub repository settings
2. Scroll to "Danger Zone"
3. Click "Change visibility" → Make public

This removes the need for authentication.
