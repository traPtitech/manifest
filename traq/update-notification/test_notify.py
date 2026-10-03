import io
import json
import os
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

import notify


class NotificationTest(unittest.TestCase):
    def setUp(self):
        self.deployment = {
            "spec": {
                "template": {
                    "spec": {
                        "containers": [{"name": "traq-backend", "image": "traq:old"}]
                    }
                }
            }
        }
        self.enterContext(patch.object(notify.Path, "read_text", return_value="traq"))
        self.enterContext(patch.object(notify.ssl, "create_default_context"))
        self.enterContext(
            patch.dict(os.environ, {"TARGET_IMAGE": "traq:new"}, clear=True)
        )
        self.urlopen = self.enterContext(patch.object(notify, "urlopen"))

    def api_response(self):
        return io.BytesIO(json.dumps(self.deployment).encode())

    def test_frontend_update_skips_notification_without_secret(self):
        os.environ["TARGET_IMAGE"] = "traq:old"
        self.urlopen.return_value = self.api_response()
        notify.main()
        self.assertEqual(self.urlopen.call_count, 1)

    def test_initial_deployment_skips_notification(self):
        self.urlopen.side_effect = HTTPError("", 404, "Not Found", {}, None)
        notify.main()
        self.assertEqual(self.urlopen.call_count, 1)

    def test_backend_update_sends_notification_and_waits_for_confirmation(self):
        os.environ["DISCORD_WEBHOOK_URL"] = (
            "https://discord.com/api/webhooks/test?wait=false"
        )
        self.urlopen.side_effect = [self.api_response(), io.BytesIO(b"{}")]
        notify.main()
        request = self.urlopen.call_args.args[0]
        self.assertEqual(
            request.full_url, "https://discord.com/api/webhooks/test?wait=true"
        )
        payload = json.loads(request.data)
        self.assertIn("`traq:old` → `traq:new`", payload["content"])
        self.assertEqual(payload["allowed_mentions"], {"parse": []})
        self.assertNotIn("Authorization", request.headers)

    def test_missing_webhook_stops_backend_update(self):
        self.urlopen.return_value = self.api_response()
        with self.assertRaises(ValueError):
            notify.main()
        self.assertEqual(self.urlopen.call_count, 1)

    def test_api_permission_error_stops_update(self):
        self.urlopen.side_effect = HTTPError("", 403, "Forbidden", {}, None)
        with self.assertRaises(HTTPError):
            notify.main()
        self.assertEqual(self.urlopen.call_count, 1)

    def test_discord_error_stops_update(self):
        os.environ["DISCORD_WEBHOOK_URL"] = "https://discord.com/api/webhooks/test"
        self.urlopen.side_effect = [
            self.api_response(),
            HTTPError("", 429, "Too Many Requests", {}, None),
        ]
        with self.assertRaises(HTTPError):
            notify.main()


if __name__ == "__main__":
    unittest.main()
