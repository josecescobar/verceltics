"""Guardrails for the VercelticsWidgets target and SharedAmbient group.

The widget extension cannot be compiled on Linux. These checks catch the project-file
mistakes that would leave Xcode unable to embed or share the ambient types.
"""

from __future__ import annotations

import plistlib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBXPROJ = ROOT / "ios" / "verceltics.xcodeproj" / "project.pbxproj"
WIDGET_INFO = ROOT / "ios" / "VercelticsWidgets" / "Info.plist"
SHARED = ROOT / "ios" / "SharedAmbient"
WIDGETS = ROOT / "ios" / "VercelticsWidgets"


class IOSWidgetTargetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.pbxproj = PBXPROJ.read_text(encoding="utf-8")

    def test_widget_product_is_an_app_extension(self) -> None:
        self.assertIn('productType = "com.apple.product-type.app-extension"', self.pbxproj)
        self.assertIn(
            "PRODUCT_BUNDLE_IDENTIFIER = com.apoorvdarshan.verceltics.VercelticsWidgets",
            self.pbxproj,
        )
        self.assertIn("path = VercelticsWidgets", self.pbxproj)
        self.assertIn("path = SharedAmbient", self.pbxproj)

    def test_app_embeds_the_widget_in_plug_ins(self) -> None:
        self.assertIn("dstSubfolderSpec = 13", self.pbxproj)
        self.assertIn("Embed Foundation Extensions", self.pbxproj)
        self.assertIn("VercelticsWidgets.appex in Embed Foundation Extensions", self.pbxproj)
        self.assertIn("APPLICATION_EXTENSION_API_ONLY = YES", self.pbxproj)
        self.assertIn("SKIP_INSTALL = YES", self.pbxproj)

    def test_shared_types_exist_once(self) -> None:
        expected = [
            "AccountProvider.swift",
            "DeploymentState.swift",
            "AmbientSnapshot.swift",
            "AmbientSnapshotStore.swift",
            "DeployActivityAttributes.swift",
            "AppTheme.swift",
        ]
        for name in expected:
            self.assertTrue((SHARED / name).is_file(), name)
            self.assertFalse((ROOT / "ios" / "verceltics" / "Models" / name).exists(), name)
            self.assertFalse((ROOT / "ios" / "verceltics" / "Ambient" / name).exists(), name)
            self.assertFalse((ROOT / "ios" / "verceltics" / "Components" / name).exists(), name)

        account = (ROOT / "ios" / "verceltics" / "Models" / "VercelAccount.swift").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("enum AccountProvider", account)

    def test_widget_sources_and_info_plist(self) -> None:
        for name in (
            "VercelticsWidgetBundle.swift",
            "DeployLiveActivity.swift",
            "DeployStatusWidget.swift",
            "Info.plist",
        ):
            self.assertTrue((WIDGETS / name).is_file(), name)

        info = plistlib.loads(WIDGET_INFO.read_bytes())
        self.assertEqual(
            info["NSExtension"]["NSExtensionPointIdentifier"],
            "com.apple.widgetkit-extension",
        )
        self.assertTrue(info["NSSupportsLiveActivities"])
        self.assertIn("Info.plist,", self.pbxproj)

    def test_widget_bundle_declares_both_surfaces(self) -> None:
        bundle = (WIDGETS / "VercelticsWidgetBundle.swift").read_text(encoding="utf-8")
        self.assertIn("DeployStatusWidget()", bundle)
        self.assertIn("DeployLiveActivity()", bundle)
        self.assertIn("@main", bundle)

        widget = (WIDGETS / "DeployStatusWidget.swift").read_text(encoding="utf-8")
        self.assertIn("verceltics://deploy/latest", widget)
        self.assertIn("AmbientSnapshotStore.read()", widget)


if __name__ == "__main__":
    unittest.main()
