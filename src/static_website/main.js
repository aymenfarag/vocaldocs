/*
MIT No Attribution

Copyright 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

/**
 * @module main
 * @description Authentication module for Cognito integration with OIDC.
 * Handles user authentication, session management, and sign-out functionality.
 */

import config from "./config.js";

/**
 * Configuration object for Amazon Cognito authentication using OIDC.
 * @type {Object}
 * @property {string} authority - The Cognito identity provider URL
 * @property {string} client_id - The Cognito user pool client ID
 * @property {string} redirect_uri - The URI to redirect to after authentication
 * @property {string} response_type - The OAuth response type (code)
 * @property {string} scope - OAuth scopes requested during authentication
 * @property {boolean} loadUserInfo - Whether to load user info
 * @property {boolean} monitorSession - Whether to monitor the session
 * @property {Object} metadata - OIDC metadata endpoints
 */
const cognitoAuthConfig = {
  authority: `https://cognito-idp.${config.REGION}.${config.PARTITION_DNS_SUFFIX}/${config.USER_POOL_ID}`,
  client_id: config.USER_POOL_CLIENT_ID,
  redirect_uri: `https://${config.CLOUDFRONT_DOMAIN}`,
  response_type: "code",
  scope: "phone openid email",
  loadUserInfo: true,
  monitorSession: false,
  metadata: {
    issuer: `https://cognito-idp.${config.REGION}.${config.PARTITION_DNS_SUFFIX}/${config.USER_POOL_ID}`,
    authorization_endpoint: `${config.COGNITO_USER_POOL_DOMAIN}/oauth2/authorize`,
    token_endpoint: `${config.COGNITO_USER_POOL_DOMAIN}/oauth2/token`,
    userinfo_endpoint: `${config.COGNITO_USER_POOL_DOMAIN}/oauth2/userInfo`,
  },
};

/**
 * OIDC UserManager instance for handling authentication operations.
 * @type {oidc.UserManager}
 * @exports userManager
 */
export const userManager = new oidc.UserManager(cognitoAuthConfig);

/**
 * Event handler for when a user is successfully loaded.
 * @param {Object} user - The loaded user object
 */
userManager.events.addUserLoaded((user) => {
  console.log("User loaded:", user);
});

/**
 * Event handler for silent token renewal errors.
 * @param {Error} error - The error that occurred during silent renewal
 */
userManager.events.addSilentRenewError((error) => {
  console.error("Silent renew error:", error);
});

/**
 * Event handler for when the access token is about to expire.
 */
userManager.events.addAccessTokenExpiring(() => {
  console.log("Access token expiring...");
});

/**
 * Event handler for when the access token has expired.
 */
userManager.events.addAccessTokenExpired(() => {
  console.log("Access token expired");
});

/**
 * Redirects the user to the sign-out page.
 * Attempts to use OIDC signoutRedirect first, and falls back to a manual redirect
 * if the OIDC method fails.
 *
 * @async
 * @function signOutRedirect
 * @returns {Promise<void>} A promise that resolves when the sign-out process is initiated
 * @exports signOutRedirect
 * @throws {Error} Logs but handles any errors during sign-out
 */
export async function signOutRedirect() {
  try {
    await userManager.signoutRedirect();
  } catch (error) {
    console.error("Error during sign out:", error);
    const clientId = config.USER_POOL_CLIENT_ID;
    const logoutUri = `https://${config.CLOUDFRONT_DOMAIN}`;
    const cognitoDomain = `${config.COGNITO_USER_POOL_DOMAIN}`;
    window.location.href = `${cognitoDomain}/logout?client_id=${clientId}&logout_uri=${encodeURIComponent(
      logoutUri
    )}`;
  }
}
