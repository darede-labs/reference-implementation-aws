{
  "id": "platform",
  "realm": "platform",
  "displayName": "Platform Realm",
  "displayNameHtml": "<div class=\"kc-logo-text\"><span>Platform</span></div>",
  "enabled": true,
  "sslRequired": "external",
  "registrationAllowed": false,
  "registrationEmailAsUsername": false,
  "rememberMe": true,
  "verifyEmail": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "permanentLockout": false,
  "maxFailureWaitSeconds": 900,
  "minimumQuickLoginWaitSeconds": 60,
  "waitIncrementSeconds": 60,
  "quickLoginCheckMilliSeconds": 1000,
  "maxDeltaTimeSeconds": 43200,
  "failureFactor": 5,
  "roles": {
    "realm": [
      {
        "name": "platform-admin",
        "description": "Platform Administrator",
        "composite": false,
        "clientRole": false,
        "containerId": "platform"
      },
      {
        "name": "platform-user",
        "description": "Platform User",
        "composite": false,
        "clientRole": false,
        "containerId": "platform"
      },
      {
        "name": "developer",
        "description": "Developer",
        "composite": false,
        "clientRole": false,
        "containerId": "platform"
      }
    ]
  },
  "groups": [
    {
      "name": "platform-team",
      "path": "/platform-team",
      "attributes": {},
      "realmRoles": ["platform-admin", "developer"],
      "clientRoles": {},
      "subGroups": []
    },
    {
      "name": "developers",
      "path": "/developers",
      "attributes": {},
      "realmRoles": ["developer", "platform-user"],
      "clientRoles": {},
      "subGroups": []
    }
  ],
  "users": [
    {
      "username": "admin",
      "enabled": true,
      "emailVerified": true,
      "firstName": "Platform",
      "lastName": "Admin",
      "email": "admin@{{ .config.domain }}",
      "credentials": [
        {
          "type": "password",
          "value": "{{ getenv "KEYCLOAK_ADMIN_PASSWORD" }}",
          "temporary": false
        }
      ],
      "realmRoles": ["platform-admin"],
      "groups": ["/platform-team"]
    }
  ],
  "clients": [
    {
      "clientId": "argocd",
      "name": "ArgoCD",
      "description": "ArgoCD GitOps Platform",
      "enabled": true,
      "clientAuthenticatorType": "client-secret",
      "secret": "{{ getenv "ARGOCD_CLIENT_SECRET" }}",
      "redirectUris": [
        "https://{{ .config.subdomains.argocd }}.{{ .config.domain }}/auth/callback"
      ],
      "webOrigins": [
        "https://{{ .config.subdomains.argocd }}.{{ .config.domain }}"
      ],
      "protocol": "openid-connect",
      "publicClient": false,
      "standardFlowEnabled": true,
      "directAccessGrantsEnabled": true,
      "fullScopeAllowed": true,
      "defaultClientScopes": [
        "web-origins",
        "profile",
        "roles",
        "email",
        "groups"
      ],
      "optionalClientScopes": [
        "address",
        "phone",
        "offline_access",
        "microprofile-jwt"
      ],
      "protocolMappers": [
        {
          "name": "argocd-groups",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-group-membership-mapper",
          "consentRequired": false,
          "config": {
            "full.path": "false",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "groups",
            "userinfo.token.claim": "true"
          }
        }
      ]
    },
    {
      "clientId": "backstage",
      "name": "Backstage IDP",
      "description": "Internal Developer Platform - Backstage",
      "enabled": true,
      "protocol": "openid-connect",
      "publicClient": false,
      "secret": "{{ getenv "BACKSTAGE_CLIENT_SECRET" }}",
      "redirectUris": [
        "https://{{ .config.subdomains.backstage }}.{{ .config.domain }}/*",
        "https://{{ .config.subdomains.backstage }}.{{ .config.domain }}/api/auth/oidc/handler/frame"
      ],
      "webOrigins": [
        "https://{{ .config.subdomains.backstage }}.{{ .config.domain }}"
      ],
      "standardFlowEnabled": true,
      "implicitFlowEnabled": false,
      "directAccessGrantsEnabled": true,
      "fullScopeAllowed": true,
      "defaultClientScopes": [
        "profile",
        "email",
        "groups"
      ],
      "optionalClientScopes": [
        "address",
        "phone",
        "offline_access",
        "microprofile-jwt"
      ],
      "protocolMappers": [
        {
          "name": "groups",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-group-membership-mapper",
          "consentRequired": false,
          "config": {
            "full.path": "false",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "groups",
            "userinfo.token.claim": "true"
          }
        },
        {
          "name": "email",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-usermodel-property-mapper",
          "consentRequired": false,
          "config": {
            "userinfo.token.claim": "true",
            "user.attribute": "email",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "email",
            "jsonType.label": "String"
          }
        }
      ]
    }
  ],
  "clientScopes": [
    {
      "name": "groups",
      "description": "User groups",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "true"
      },
      "protocolMappers": [
        {
          "name": "groups",
          "protocol": "openid-connect",
          "protocolMapper": "oidc-group-membership-mapper",
          "consentRequired": false,
          "config": {
            "full.path": "false",
            "id.token.claim": "true",
            "access.token.claim": "true",
            "claim.name": "groups",
            "userinfo.token.claim": "true"
          }
        }
      ]
    }
  ],
  "defaultDefaultClientScopes": [
    "role_list",
    "profile",
    "email",
    "groups"
  ],
  "defaultOptionalClientScopes": [
    "offline_access",
    "address",
    "phone",
    "microprofile-jwt"
  ],
  "browserSecurityHeaders": {
    "contentSecurityPolicyReportOnly": "",
    "xContentTypeOptions": "nosniff",
    "xRobotsTag": "none",
    "xFrameOptions": "SAMEORIGIN",
    "contentSecurityPolicy": "frame-src 'self'; frame-ancestors 'self'; object-src 'none';",
    "xXSSProtection": "1; mode=block",
    "strictTransportSecurity": "max-age=31536000; includeSubDomains"
  },
  "smtpServer": {},
  "eventsEnabled": true,
  "eventsListeners": ["jboss-logging"],
  "enabledEventTypes": [
    "LOGIN",
    "LOGIN_ERROR",
    "LOGOUT",
    "LOGOUT_ERROR"
  ],
  "adminEventsEnabled": true,
  "adminEventsDetailsEnabled": true,
  "internationalizationEnabled": false,
  "supportedLocales": ["en"],
  "defaultLocale": "en",
  "authenticationFlows": [],
  "attributes": {
    "frontendUrl": "https://{{ .config.subdomains.keycloak }}.{{ .config.domain }}"
  }
}
