import config from './config.js';

const cognitoAuthConfig = {
    authority: `https://cognito-idp.${config.REGION}.amazonaws.com/${config.USER_POOL_ID}`,
    client_id: config.USER_POOL_CLIENT_ID,
    redirect_uri: `https://${config.CLOUDFRONT_DOMAIN}`,
    response_type: "code",
    scope: "phone openid email",
    loadUserInfo: true,
    monitorSession: false,
    metadata: {
        issuer: `https://cognito-idp.${config.REGION}.amazonaws.com/${config.USER_POOL_ID}`,
        authorization_endpoint: `${config.COGNITO_USER_POOL_DOMAIN}/oauth2/authorize`,
        token_endpoint: `${config.COGNITO_USER_POOL_DOMAIN}/oauth2/token`,
        userinfo_endpoint: `${config.COGNITO_USER_POOL_DOMAIN}/oauth2/userInfo`
    }
};

// create a UserManager instance
export const userManager = new oidc.UserManager(cognitoAuthConfig);

userManager.events.addUserLoaded((user) => {
    console.log("User loaded:", user);
});

userManager.events.addSilentRenewError((error) => {
    console.error("Silent renew error:", error);
});

userManager.events.addAccessTokenExpiring(() => {
    console.log("Access token expiring...");
});

userManager.events.addAccessTokenExpired(() => {
    console.log("Access token expired");
});

export async function signOutRedirect() {
    try {
        await userManager.signoutRedirect();
    } catch (error) {
        console.error("Error during sign out:", error);
        const clientId = config.USER_POOL_CLIENT_ID;
        const logoutUri = `https://${config.CLOUDFRONT_DOMAIN}`;
        const cognitoDomain = `${config.COGNITO_USER_POOL_DOMAIN}`;
        window.location.href = `${cognitoDomain}/logout?client_id=${clientId}&logout_uri=${encodeURIComponent(logoutUri)}`;
    }
}