// amplify/storage/resource.ts
import { defineStorage } from "@aws-amplify/backend";

export const storage = defineStorage({
  name: "amplifyTeamDrive", // A friendly name for your S3 bucket
  access: (allow) => ({
    // Example: Everyone can read and write to "picture-submissions" path
    "picture-submissions/*": [
      allow.guest.to(["read", "write"]),
      allow.authenticated.to(["read", "write"]),
    ],
  }),
});
