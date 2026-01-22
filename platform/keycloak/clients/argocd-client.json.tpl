{
  "clientId": "argocd",
  "name": "ArgoCD",
  "description": "ArgoCD GitOps Platform",
  "enabled": true,
  "clientAuthenticatorType": "client-secret",
  "secret": "{{ argocd_client_secret }}",
  "redirectUris": [
    "https://{{ argocd_subdomain }}.{{ domain }}/auth/callback",
    "https://{{ argocd_subdomain }}.{{ domain }}/api/dex/callback"
  ],
  "webOrigins": [
    "https://{{ argocd_subdomain }}.{{ domain }}"
  ],
  "protocol": "openid-connect",
  "publicClient": false,
  "frontchannelLogout": true,
  "attributes": {
    "saml.assertion.signature": "false",
    "saml.multivalued.roles": "false",
    "saml.force.post.binding": "false",
    "saml.encrypt": "false",
    "oauth2.device.authorization.grant.enabled": "false",
    "backchannel.logout.revoke.offline.tokens": "false",
    "saml.server.signature": "false",
    "saml.server.signature.keyinfo.ext": "false",
    "use.refresh.tokens": "true",
    "exclude.session.state.from.auth.response": "false",
    "oidc.ciba.grant.enabled": "false",
    "saml.artifact.binding": "false",
    "backchannel.logout.session.required": "true",
    "client_credentials.use_refresh_token": "false",
    "saml_force_name_id_format": "false",
    "require.pushed.authorization.requests": "false",
    "saml.client.signature": "false",
    "tls.client.certificate.bound.access.tokens": "false",
    "saml.authnstatement": "false",
    "display.on.consent.screen": "false",
    "saml.onetimeuse.condition": "false"
  },
  "authenticationFlowBindingOverrides": {},
  "fullScopeAllowed": true,
  "nodeReRegistrationTimeout": -1,
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
}
