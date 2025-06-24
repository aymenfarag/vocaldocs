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
 * @module script
 * @description Main application script for the VocalDocs web interface.
 * Handles user authentication, file uploads, request tracking, and UI interactions.
 */

import { userManager, signOutRedirect } from "./main.js";
import config from "./config.js";

console.log("Script started");

/**
 * Safely sets the text content of an element, with error handling if element doesn't exist.
 *
 * @param {string} id - The ID of the DOM element to update
 * @param {string} text - The text content to set
 */
function safeSetTextContent(id, text) {
  const element = document.getElementById(id);
  if (element) {
    element.textContent = text;
  } else {
    console.warn(`Element with id '${id}' not found`);
  }
}

/**
 * Updates the UI with user information from the authentication profile.
 *
 * @param {Object} user - The authenticated user object
 * @param {Object} user.profile - The user profile information
 * @param {string} [user.profile.email] - The user's email address
 */
function updateUserInfo(user) {
  console.log("Updating user info");
  safeSetTextContent("email", user.profile?.email);
}

/**
 * Shows the main content area and hides the login section.
 * Used after successful authentication.
 */
function showMainContent() {
  const loginSection = document.getElementById("loginSection");
  const mainContent = document.getElementById("mainContent");

  if (loginSection) {
    loginSection.style.display = "none";
  } else {
    console.warn("Element with id 'loginSection' not found");
  }

  if (mainContent) {
    mainContent.style.display = "block";
  } else {
    console.warn("Element with id 'mainContent' not found");
  }
}

/**
 * Temporarily disables the submit button to prevent multiple submissions.
 *
 * @param {number} duration - The duration in milliseconds to disable the button
 */
function disableSubmitButton(duration) {
  const submitButton = document.querySelector(
    '#newRequestForm button[type="submit"]'
  );
  submitButton.disabled = true;
  submitButton.textContent = "Please wait...";
  setTimeout(() => {
    submitButton.disabled = false;
    submitButton.textContent = "Submit";
  }, duration);
}

/**
 * Main initialization function that runs when the DOM content is loaded.
 * Sets up event listeners, handles authentication flow, and initializes the UI.
 */
document.addEventListener("DOMContentLoaded", function () {
  console.log("DOM content loaded");

  const buttons = document.querySelectorAll(".button");
  buttons.forEach((button) => {
    button.addEventListener("mouseenter", () => {
      button.classList.add("animate__animated", "animate__pulse");
    });
    button.addEventListener("mouseleave", () => {
      button.classList.remove("animate__animated", "animate__pulse");
    });
  });

  const signInButton = document.getElementById("signIn");
  if (signInButton) {
    signInButton.addEventListener("click", async () => {
      console.log("Sign In button clicked");
      try {
        console.log("Initiating sign-in redirect...");
        await userManager.signinRedirect();
      } catch (error) {
        console.error("Error during sign in redirect:", error);
      }
    });
  }

  const signOutButton = document.getElementById("signOut");
  if (signOutButton) {
    signOutButton.addEventListener("click", async () => {
      await signOutRedirect();
    });
  }

  const newRequestForm = document.getElementById("newRequestForm");
  if (newRequestForm) {
    newRequestForm.addEventListener("submit", handleNewRequest);
  }

  if (window.location.href.includes("code=")) {
    userManager
      .signinCallback()
      .then(function (user) {
        if (user) {
          console.log("User logged in:", user);
          updateUserInfo(user);
          showMainContent();
          configureAWS(user);
        }
      })
      .catch(function (error) {
        console.error("Error during signin callback:", error);
      });
  } else {
    userManager.getUser().then(function (user) {
      if (user) {
        console.log("User already logged in:", user);
        updateUserInfo(user);
        showMainContent();
        configureAWS(user);

        if (window.location.pathname.includes("track-request.html")) {
          fetchUserRequests(user);
        }
      }
    });
  }
});

/**
 * Configures AWS SDK with user credentials from Cognito.
 * Sets up the AWS credentials provider chain for authenticated API calls.
 *
 * @param {Object} user - The authenticated user object
 * @param {string} user.id_token - The ID token from Cognito authentication
 */
function configureAWS(user) {
  console.log("Configuring AWS...");
  console.log("User:", user);

  const loginKey = `cognito-idp.${config.REGION}.${config.PARTITION_DNS_SUFFIX}/${config.USER_POOL_ID}`;

  AWS.config.region = config.REGION;
  AWS.config.credentials = new AWS.CognitoIdentityCredentials({
    IdentityPoolId: config.IDENTITY_POOL_ID,
    Logins: {
      [loginKey]: user.id_token,
    },
  });

  console.log("AWS Config:", AWS.config);

  AWS.config.credentials.refresh((error) => {
    if (error) {
      console.error("Error refreshing credentials:", error);
      console.error("Error details:", JSON.stringify(error, null, 2));
    } else {
      console.log("Successfully logged in and obtained credentials");
      console.log("Credentials:", AWS.config.credentials);
    }
  });
}

/**
 * Handles the submission of a new document processing request.
 * Validates the file, prepares the payload, and invokes the Lambda function.
 *
 * @param {Event} e - The form submission event
 */
function handleNewRequest(e) {
  e.preventDefault();
  console.log("Handling new request submission");

  disableSubmitButton(60000);

  const fileInput = document.getElementById("fileUpload");
  const file = fileInput.files[0];
  const fileError = document.getElementById("fileError");
  const language = document.querySelector(
    'input[name="language"]:checked'
  ).value;
  const startPage = document.getElementById("startPage").value;
  const endPage = document.getElementById("endPage").value;
  const responseMessage = document.getElementById("responseMessage");

  console.log("File:", file ? file.name : "No file selected");
  console.log("Language:", language);
  console.log("Start Page:", startPage);
  console.log("End Page:", endPage);

  fileError.textContent = "";

  if (!validateFile(file, fileError)) {
    console.log("File validation failed");
    return;
  }

  console.log("File validated successfully");

  userManager.getUser().then(function (user) {
    if (!user) {
      console.error("No user logged in");
      responseMessage.textContent = "Please log in to submit a request.";
      return;
    }

    const payload = {
      fileName: file.name,
      language: language,
      startPage: startPage,
      endPage: endPage,
      fileContent: null,
      username: user.profile.email,
    };

    const reader = new FileReader();
    reader.onload = function (event) {
      payload.fileContent = event.target.result.split(",")[1];
      console.log("File read as base64");
      console.log("Payload prepared:", JSON.stringify(payload, null, 2));
      invokeLambda(payload, responseMessage);
    };
    reader.onerror = function (event) {
      console.error("Error reading file:", event.target.error);
      responseMessage.textContent = "Error reading file. Please try again.";
    };
    reader.readAsDataURL(file);
  });
}

/**
 * Validates the uploaded file for size and type constraints.
 *
 * @param {File} file - The file object to validate
 * @param {HTMLElement} fileError - The DOM element to display error messages
 * @returns {boolean} True if the file is valid, false otherwise
 */
function validateFile(file, fileError) {
  console.log("Validating file");
  if (!file) {
    console.log("No file selected");
    fileError.textContent = "Please select a file.";
    return false;
  }
  if (file.size > 5 * 1024 * 1024) {
    console.log("File size exceeds limit");
    fileError.textContent = "File size exceeds 5MB limit.";
    return false;
  }
  const allowedTypes = [
    "application/pdf",
    "application/msword",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  ];
  if (!allowedTypes.includes(file.type)) {
    console.log("Invalid file type:", file.type);
    fileError.textContent = "Only PDF and Word documents are allowed.";
    return false;
  }
  console.log("File validation passed");
  return true;
}

/**
 * Invokes the Lambda function to process the document request.
 * Handles response parsing and error handling.
 *
 * @param {Object} payload - The request payload to send to Lambda
 * @param {HTMLElement} responseMessage - The DOM element to display response messages
 */
function invokeLambda(payload, responseMessage) {
  console.log("Invoking Lambda function");
  const lambda = new AWS.Lambda({ region: config.REGION });
  const params = {
    FunctionName: config.UPLOAD_LAMBDA_NAME,
    InvocationType: "RequestResponse",
    Payload: JSON.stringify(payload),
  };

  console.log("Lambda invoke params:", JSON.stringify(params, null, 2));

  lambda.invoke(params, function (err, data) {
    if (err) {
      console.error("Error invoking Lambda function:", err);
      responseMessage.textContent = `An error occurred: ${err.message}`;
    } else {
      console.log("Lambda function response:", data);
      if (data.FunctionError) {
        console.error("Lambda function error:", data.Payload);
        try {
          const errorPayload = JSON.parse(data.Payload);
          if (errorPayload.errorType === "Sandbox.Timedout") {
            responseMessage.textContent =
              "The request timed out. Please try again or contact support if the issue persists.";
          } else {
            responseMessage.textContent = `An error occurred in the Lambda function: ${errorPayload.errorMessage}`;
          }
        } catch (parseError) {
          responseMessage.textContent = `An error occurred in the Lambda function: ${data.FunctionError}`;
        }
      } else {
        try {
          const response = JSON.parse(data.Payload);
          if (response.statusCode === 200) {
            const body = JSON.parse(response.body);
            console.log("Request processed successfully");
            responseMessage.innerHTML = `${body.message}<br>Tracking reference key: ${body.reference_key}`;
          } else {
            console.log("Failed to process request");
            responseMessage.textContent = `Failed to process request: ${response.body}`;
          }
        } catch (parseError) {
          console.error("Error parsing Lambda response:", parseError);
          responseMessage.textContent =
            "An error occurred while processing the response";
        }
      }
    }
  });
}

/**
 * Fetches the user's document processing requests from the backend.
 *
 * @async
 * @function fetchUserRequests
 * @param {Object} user - The authenticated user object
 * @param {Object} user.profile - The user profile information
 * @param {string} user.profile.email - The user's email address
 * @exports fetchUserRequests
 */
export async function fetchUserRequests(user) {
  console.log("Fetching user requests");
  const lambda = new AWS.Lambda({ region: config.REGION });
  const params = {
    FunctionName: config.TRACK_LAMBDA_NAME,
    InvocationType: "RequestResponse",
    Payload: JSON.stringify({ username: user.profile.email }),
  };

  lambda.invoke(params, function (err, data) {
    if (err) {
      console.error("Error invoking Lambda function:", err);
      document.getElementById(
        "requestsTableBody"
      ).innerHTML = `<tr><td colspan="3">An error occurred: ${err.message}</td></tr>`;
    } else {
      console.log("Raw Lambda response:", data);
      try {
        const response = JSON.parse(data.Payload);
        console.log("Parsed Payload:", response);

        if (response.statusCode === 200) {
          // Parse the nested body string
          const body = JSON.parse(response.body);
          console.log("Parsed body:", body);
          console.log("Requests array:", body.requests);

          displayUserRequests(body.requests);
        } else {
          document.getElementById(
            "requestsTableBody"
          ).innerHTML = `<tr><td colspan="3">An error occurred: ${response.body}</td></tr>`;
        }
      } catch (parseError) {
        console.error("Error parsing Lambda response:", parseError);
        console.error("Parse error details:", parseError.message);
        document.getElementById("requestsTableBody").innerHTML =
          '<tr><td colspan="3">An error occurred while processing the response</td></tr>';
      }
    }
  });
}

/**
 * Displays the user's document processing requests in the UI table.
 * Adds download buttons for completed requests.
 *
 * @param {Array<Object>} requests - Array of request objects to display
 * @param {string} [requests[].fileName] - The name of the uploaded file
 * @param {string} requests[].reference_key - The unique reference key for the request
 * @param {string} requests[].TaskStatus - The current status of the processing task
 */
function displayUserRequests(requests) {
  console.log("Inside displayUserRequests - requests:", requests);
  const tableBody = document.getElementById("requestsTableBody");
  tableBody.innerHTML = "";

  if (!requests || requests.length === 0) {
    tableBody.innerHTML = '<tr><td colspan="4">No requests found</td></tr>';
    return;
  }

  requests.forEach((request) => {
    console.log("Processing request:", request);

    // Create table row
    const row = document.createElement("tr");

    // Set row HTML with correct data placement
    row.innerHTML = `
            <td>${request.fileName || "Unknown File"}</td>
            <td>${request.reference_key}</td>
            <td>${request.TaskStatus}</td>
            <td>
                ${
                  request.TaskStatus === "Voice-is-Ready"
                    ? `<button class="download-button button" data-reference-key="${request.reference_key}">Download</button>`
                    : "Not ready yet"
                }
            </td>
        `;

    tableBody.appendChild(row);
  });

  // Add event listeners to download buttons
  document.querySelectorAll(".download-button").forEach((button) => {
    button.addEventListener("click", function () {
      generateDownloadLink(this.dataset.referenceKey);
    });
  });
}

/**
 * Generates a download link for a completed document processing request.
 * Invokes the Lambda function to get a presigned URL and opens it in a new tab.
 *
 * @async
 * @function generateDownloadLink
 * @param {string} referenceKey - The unique reference key for the request
 * @exports generateDownloadLink
 */
export async function generateDownloadLink(referenceKey) {
  console.log("Generating download link for:", referenceKey);
  const lambda = new AWS.Lambda({ region: config.REGION });
  const params = {
    FunctionName: config.TRACK_LAMBDA_NAME,
    InvocationType: "RequestResponse",
    Payload: JSON.stringify({
      action: "generate_url",
      reference_key: referenceKey,
    }),
  };

  console.log("Invoking Lambda with params:", JSON.stringify(params, null, 2));

  lambda.invoke(params, function (err, data) {
    if (err) {
      console.error("Error invoking Lambda function:", err);
      alert(
        "An error occurred while generating the download link. Please try again."
      );
    } else {
      console.log("Lambda function response:", JSON.stringify(data, null, 2));
      try {
        const response = JSON.parse(data.Payload);
        if (response.statusCode === 200) {
          const body = JSON.parse(response.body);
          if (body.presigned_url) {
            // Open the presigned URL in a new tab
            window.open(body.presigned_url, "_blank");
          } else {
            alert("No download URL available. Please try again later.");
          }
        } else {
          alert("Failed to generate download link. Please try again.");
        }
      } catch (parseError) {
        console.error("Error parsing Lambda response:", parseError);
        alert(
          "An error occurred while processing the response. Please try again."
        );
      }
    }
  });
}

console.log("Script ended");
