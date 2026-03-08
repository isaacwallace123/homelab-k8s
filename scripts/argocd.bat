@echo off
echo =====================================
echo   ArgoCD Port Forward Helper
echo =====================================
echo.

echo Checking kubectl...
kubectl version --client >nul 2>&1
if %errorlevel% neq 0 (
echo ERROR: kubectl not found in PATH.
pause
exit /b
)

echo Starting port forward...
echo Access ArgoCD at: https://localhost:8080
echo Press CTRL+C to stop.
echo.

start /b cmd /c "timeout /t 2 /nobreak >nul && start https://localhost:8080"
kubectl port-forward svc/argocd-server -n argocd 8080:443

PAUSE
