import WebKit
import XCTest
@testable import SideCord

@MainActor
final class WebCSSRuntimeTests: XCTestCase {
    func testIncomingCallBridgeTracksOnlyIncomingRingingState() async throws {
        let recorder = RuntimeMessageRecorder()
        let (webView, navigationWaiter) = try await loadFixture(messageRecorder: recorder)
        _ = navigationWaiter
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.userScriptSource(
                css: try runtimeCSS(customCSS: ""),
                configuration: makeConfiguration(navigation: .docked, composer: .full)
            )
        )
        try await waitForRuntime()

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const outgoing = document.createElement('div');
              outgoing.id = 'outgoing-call';
              outgoing.className = 'ringingOutgoing_fixture';
              document.body.appendChild(outgoing);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertTrue(recorder.incomingCallStates.isEmpty)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const incoming = document.createElement('div');
              incoming.id = 'incoming-call';
              incoming.className = 'ringingIncoming_fixture';
              incoming.style.cssText =
                'position: fixed; top: 20px; left: 20px; width: 240px; height: 80px';
              document.body.appendChild(incoming);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.incomingCallStates, [true])

        _ = try await webView.evaluateJavaScript(
            "document.getElementById('incoming-call').classList.add('rerender_fixture')"
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.incomingCallStates, [true])

        _ = try await webView.evaluateJavaScript(
            "document.getElementById('incoming-call').remove()"
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.incomingCallStates, [true, false])

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const accessibleIncoming = document.createElement('div');
              accessibleIncoming.id = 'accessible-incoming-call';
              accessibleIncoming.setAttribute('role', 'dialog');
              accessibleIncoming.setAttribute('aria-label', 'Incoming call from Fixture');
              accessibleIncoming.style.cssText =
                'position: fixed; top: 20px; left: 20px; width: 240px; height: 80px';
              document.body.appendChild(accessibleIncoming);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.incomingCallStates, [true, false, true])

        _ = try await webView.evaluateJavaScript(
            "document.getElementById('accessible-incoming-call').setAttribute('aria-hidden', 'true')"
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.incomingCallStates, [true, false, true, false])

        _ = try await webView.evaluateJavaScript(
            "document.getElementById('accessible-incoming-call').remove()"
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.incomingCallStates, [true, false, true, false])

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const hiddenContainer = document.createElement('div');
              hiddenContainer.id = 'hidden-call-container';
              hiddenContainer.setAttribute('aria-hidden', 'true');
              const cachedIncoming = document.createElement('div');
              cachedIncoming.className = 'ringingIncoming_cached';
              cachedIncoming.style.cssText =
                'position: fixed; top: 20px; left: 20px; width: 240px; height: 80px';
              hiddenContainer.appendChild(cachedIncoming);
              document.body.appendChild(hiddenContainer);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.incomingCallStates, [true, false, true, false])

        _ = try await webView.evaluateJavaScript(
            "document.getElementById('hidden-call-container').removeAttribute('aria-hidden')"
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.incomingCallStates, [true, false, true, false, true])

        _ = try await webView.evaluateJavaScript(
            "document.getElementById('hidden-call-container').style.opacity = '0'"
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.incomingCallStates, [true, false, true, false, true, false])
    }

    func testNotificationBridgeReportsNoNotificationContentAndPreservesConstructor() async throws {
        let recorder = RuntimeMessageRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(
            recorder,
            name: DiscordCSSComposer.messageHandlerName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                (() => {
                  class FixtureNotification {
                    constructor(title) {
                      if (title === 'throw') throw new Error('fixture failure');
                      this.title = title;
                    }
                    static permission = 'granted';
                    static requestPermission() { return Promise.resolve('granted'); }
                  }
                  class FixtureServiceWorkerRegistration {
                    constructor(scope = 'https://discord.com/') {
                      this.scope = scope;
                    }
                    showNotification(title) {
                      window.fixtureServiceWorkerCallCount += 1;
                      if (title === 'throw') return Promise.reject(new Error('fixture failure'));
                      window.fixtureNotificationTimestamp += 1;
                      window.fixtureServiceWorkerNotifications = [{
                        tag: 'fixture-notification',
                        timestamp: window.fixtureNotificationTimestamp
                      }];
                      return Promise.resolve('shown');
                    }
                    getNotifications() {
                      return Promise.resolve(window.fixtureServiceWorkerNotifications);
                    }
                  }
                  window.fixtureServiceWorkerCallCount = 0;
                  window.fixtureNotificationTimestamp = 0;
                  window.fixtureServiceWorkerNotifications = [];
                  window.Notification = FixtureNotification;
                  window.fixtureOriginalNotification = FixtureNotification;
                  window.ServiceWorkerRegistration = FixtureServiceWorkerRegistration;
                  window.fixtureServiceWorkerRegistration =
                    new FixtureServiceWorkerRegistration();
                  window.fixtureServiceWorkerRegistrations = [
                    window.fixtureServiceWorkerRegistration
                  ];
                  Object.defineProperty(navigator, 'serviceWorker', {
                    configurable: true,
                    value: {
                      getRegistrations: () => Promise.resolve(
                        [...window.fixtureServiceWorkerRegistrations]
                      )
                    }
                  });
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: DiscordCSSComposer.notificationBridgeUserScriptSource(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Notification bridge fixture loaded")
        let navigationWaiter = RuntimeNavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = navigationWaiter
        webView.loadHTMLString(
            "<!doctype html><html><body></body></html>",
            baseURL: URL(string: "https://discord.com/app")!
        )
        await fulfillment(of: [loaded], timeout: 5)
        let serviceWorkerNotificationsAreBaselined = try await
            waitForServiceWorkerNotificationBaseline(in: webView)
        XCTAssertTrue(serviceWorkerNotificationsAreBaselined)

        let state = try await webView.evaluateJavaScript(
            """
            (() => {
              const instance = new Notification('private title', { body: 'private body' });
              return {
                isOriginalInstance: instance instanceof window.fixtureOriginalNotification,
                permission: Notification.permission,
                requestPermissionPreserved:
                  Notification.requestPermission ===
                    window.fixtureOriginalNotification.requestPermission
              };
            })()
            """
        ) as! [String: Any]
        try await waitForRuntime()

        XCTAssertEqual(state["isOriginalInstance"] as? Bool, true)
        XCTAssertEqual(state["permission"] as? String, "granted")
        XCTAssertEqual(state["requestPermissionPreserved"] as? Bool, true)
        XCTAssertEqual(recorder.notificationPayloads.count, 1)
        XCTAssertEqual(Set(recorder.notificationPayloads[0].keys), ["type"])

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const historicalRegistration = {
                scope: 'https://discord.com/historical-worker/',
                getNotifications: () => Promise.resolve([{
                  tag: 'historical-notification',
                  timestamp: 1
                }])
              };
              window.fixtureServiceWorkerRegistrations.unshift(
                historicalRegistration
              );
              return true;
            })()
            """
        )
        try await Task.sleep(for: .milliseconds(1_100))
        XCTAssertEqual(recorder.notificationPayloads.count, 1)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              new ServiceWorkerRegistration().showNotification(
                'private service title',
                { body: 'private service body' }
              );
              return true;
            })()
            """
        )
        let serviceWorkerNotificationWasReported = try await waitForNotificationCount(
            2,
            recorder: recorder
        )
        XCTAssertTrue(serviceWorkerNotificationWasReported)
        let serviceWorkerState = try await webView.evaluateJavaScript(
            """
            ({
              callCount: window.fixtureServiceWorkerCallCount
            })
            """
        ) as! [String: Any]
        XCTAssertEqual(serviceWorkerState["callCount"] as? Int, 1)
        XCTAssertEqual(recorder.notificationPayloads.count, 2)
        XCTAssertEqual(Set(recorder.notificationPayloads[1].keys), ["type"])

        do {
            _ = try await webView.evaluateJavaScript("new Notification('throw')")
            XCTFail("Expected the fixture notification constructor to throw")
        } catch {
            // A failed constructor must not produce a native attention event.
        }
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 2)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              new ServiceWorkerRegistration()
                .showNotification('throw')
                .catch(() => {});
              return true;
            })()
            """
        )
        try await Task.sleep(for: .milliseconds(1_100))
        XCTAssertEqual(recorder.notificationPayloads.count, 2)
        _ = navigationWaiter
    }

    func testNotificationBridgeConnectsDiscordWhenWebPermissionIsUnavailable() async throws {
        let recorder = RuntimeMessageRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(
            recorder,
            name: DiscordCSSComposer.messageHandlerName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                (() => {
                  class FixtureNotification {
                    static permission = 'default';
                    static requestPermission(callback) {
                      window.fixtureOriginalRequestCount += 1;
                      if (typeof callback === 'function') callback('denied');
                      return Promise.resolve('denied');
                    }
                    constructor(title) {
                      window.fixtureOriginalConstructionCount += 1;
                      if (FixtureNotification.permission !== 'granted') {
                        throw new Error('Web notification permission unavailable');
                      }
                      this.title = title;
                    }
                  }
                  window.fixtureOriginalConstructionCount = 0;
                  window.fixtureOriginalRequestCount = 0;
                  window.fixtureShowCount = 0;
                  window.fixtureCloseCount = 0;
                  window.fixturePermissionCallback = null;
                  window.Notification = FixtureNotification;
                  window.fixtureOriginalNotification = FixtureNotification;
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: DiscordCSSComposer.notificationBridgeUserScriptSource(
                    isEnabled: false
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Permission-gated notification fixture loaded")
        let navigationWaiter = RuntimeNavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = navigationWaiter
        webView.loadHTMLString(
            "<!doctype html><html><body></body></html>",
            baseURL: URL(string: "https://discord.com/app")!
        )
        await fulfillment(of: [loaded], timeout: 5)

        let disabledState = try await webView.evaluateJavaScript(
            """
            (() => {
              const DiscordNotification = Notification;
              window.fixtureDiscordNotification = DiscordNotification;
              let constructionThrew = false;
              try {
                new DiscordNotification('disabled notification');
              } catch (_) {
                constructionThrew = true;
              }
              DiscordNotification.requestPermission(permission => {
                window.fixturePermissionCallback = permission;
              });
              const bridge = window['\(DiscordCSSComposer.notificationBridgeKey)'];
              return {
                permission: DiscordNotification.permission,
                enabled: bridge.enabled,
                captures: bridge.capturesPageNotifications,
                usesVirtualPermission: bridge.usesVirtualPermission,
                constructionThrew,
                constructionCount: window.fixtureOriginalConstructionCount,
                requestCount: window.fixtureOriginalRequestCount,
                permissionCallback: window.fixturePermissionCallback
              };
            })()
            """
        ) as! [String: Any]
        XCTAssertEqual(disabledState["permission"] as? String, "default")
        XCTAssertEqual(disabledState["enabled"] as? Bool, false)
        XCTAssertEqual(disabledState["captures"] as? Bool, true)
        XCTAssertEqual(disabledState["usesVirtualPermission"] as? Bool, true)
        XCTAssertEqual(disabledState["constructionThrew"] as? Bool, true)
        XCTAssertEqual(disabledState["constructionCount"] as? Int, 1)
        XCTAssertEqual(disabledState["requestCount"] as? Int, 1)
        XCTAssertEqual(disabledState["permissionCallback"] as? String, "denied")
        XCTAssertTrue(recorder.notificationPayloads.isEmpty)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.notificationBridgeUserScriptSource(isEnabled: true)
        )
        let enabledState = try await webView.evaluateJavaScript(
            """
            (() => {
              const DiscordNotification = window.fixtureDiscordNotification;
              let instance = null;
              if (DiscordNotification.permission === 'granted') {
                instance = new DiscordNotification(
                  'private Discord title',
                  {
                    body: 'private Discord body',
                    tag: 'message',
                    navigate: 'https://discord.com/channels/1/2',
                    vibrate: [120, 40, 120]
                  }
                );
                instance.onshow = () => { window.fixtureShowCount += 1; };
                instance.onclose = () => { window.fixtureCloseCount += 1; };
                window.fixtureVirtualNotification = instance;
              }
              const bridge = window['\(DiscordCSSComposer.notificationBridgeKey)'];
              return {
                permission: DiscordNotification.permission,
                enabled: bridge.enabled,
                cachedConstructorPreserved: DiscordNotification === Notification,
                isOriginalInstance:
                  instance instanceof window.fixtureOriginalNotification,
                constructionCount: window.fixtureOriginalConstructionCount,
                navigate: instance.navigate,
                vibrate: [...instance.vibrate],
                vibrateIsFrozen: Object.isFrozen(instance.vibrate),
                silentIsNull: instance.silent === null
              };
            })()
            """
        ) as! [String: Any]
        try await waitForRuntime()

        XCTAssertEqual(enabledState["permission"] as? String, "granted")
        XCTAssertEqual(enabledState["enabled"] as? Bool, true)
        XCTAssertEqual(enabledState["cachedConstructorPreserved"] as? Bool, true)
        XCTAssertEqual(enabledState["isOriginalInstance"] as? Bool, true)
        XCTAssertEqual(enabledState["constructionCount"] as? Int, 1)
        XCTAssertEqual(
            enabledState["navigate"] as? String,
            "https://discord.com/channels/1/2"
        )
        XCTAssertEqual(enabledState["vibrate"] as? [Int], [120, 40, 120])
        XCTAssertEqual(enabledState["vibrateIsFrozen"] as? Bool, true)
        XCTAssertEqual(enabledState["silentIsNull"] as? Bool, true)
        XCTAssertEqual(recorder.notificationPayloads.count, 1)
        XCTAssertEqual(Set(recorder.notificationPayloads[0].keys), ["type"])

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              window.fixtureDiscordNotification.requestPermission(permission => {
                window.fixturePermissionCallback = permission;
              });
              window.fixtureVirtualNotification.close();
            })()
            """
        )
        try await waitForRuntime()
        let lifecycleState = try await webView.evaluateJavaScript(
            """
            ({
              showCount: window.fixtureShowCount,
              closeCount: window.fixtureCloseCount,
              permissionCallback: window.fixturePermissionCallback,
              originalRequestCount: window.fixtureOriginalRequestCount
            })
            """
        ) as! [String: Any]
        XCTAssertEqual(lifecycleState["showCount"] as? Int, 1)
        XCTAssertEqual(lifecycleState["closeCount"] as? Int, 1)
        XCTAssertEqual(lifecycleState["permissionCallback"] as? String, "granted")
        XCTAssertEqual(lifecycleState["originalRequestCount"] as? Int, 1)

        let permissionRefreshState = try await webView.evaluateJavaScript(
            """
            (() => {
              const DiscordNotification = window.fixtureDiscordNotification;
              window.fixtureOriginalNotification.permission = 'granted';
              const originalInstance = new DiscordNotification('real permission');
              window.fixtureOriginalNotification.permission = 'default';
              const virtualInstance = new DiscordNotification('virtual permission');
              virtualInstance.close();
              const bridge = window['\(DiscordCSSComposer.notificationBridgeKey)'];
              return {
                originalInstance:
                  originalInstance instanceof window.fixtureOriginalNotification,
                virtualInstance:
                  virtualInstance instanceof window.fixtureOriginalNotification,
                constructionCount: window.fixtureOriginalConstructionCount,
                permission: DiscordNotification.permission,
                usesVirtualPermission: bridge.usesVirtualPermission
              };
            })()
            """
        ) as! [String: Any]
        try await waitForRuntime()
        XCTAssertEqual(permissionRefreshState["originalInstance"] as? Bool, true)
        XCTAssertEqual(permissionRefreshState["virtualInstance"] as? Bool, true)
        XCTAssertEqual(permissionRefreshState["constructionCount"] as? Int, 2)
        XCTAssertEqual(permissionRefreshState["permission"] as? String, "granted")
        XCTAssertEqual(permissionRefreshState["usesVirtualPermission"] as? Bool, true)
        XCTAssertEqual(recorder.notificationPayloads.count, 3)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.notificationBridgeUserScriptSource(isEnabled: false)
        )
        let stateAfterDisabling = try await webView.evaluateJavaScript(
            """
            (() => {
              const DiscordNotification = window.fixtureDiscordNotification;
              let constructionThrew = false;
              try {
                new DiscordNotification('disabled again');
              } catch (_) {
                constructionThrew = true;
              }
              DiscordNotification.requestPermission(permission => {
                window.fixturePermissionCallback = permission;
              });
              return {
                permission: DiscordNotification.permission,
                cachedConstructorPreserved: DiscordNotification === Notification,
                constructionThrew,
                constructionCount: window.fixtureOriginalConstructionCount,
                requestCount: window.fixtureOriginalRequestCount,
                permissionCallback: window.fixturePermissionCallback
              };
            })()
            """
        ) as! [String: Any]
        XCTAssertEqual(stateAfterDisabling["permission"] as? String, "default")
        XCTAssertEqual(stateAfterDisabling["cachedConstructorPreserved"] as? Bool, true)
        XCTAssertEqual(stateAfterDisabling["constructionThrew"] as? Bool, true)
        XCTAssertEqual(stateAfterDisabling["constructionCount"] as? Int, 3)
        XCTAssertEqual(stateAfterDisabling["requestCount"] as? Int, 2)
        XCTAssertEqual(stateAfterDisabling["permissionCallback"] as? String, "denied")
        XCTAssertEqual(recorder.notificationPayloads.count, 3)
        _ = navigationWaiter
    }

    func testDisabledNotificationBridgePreservesMissingWebAPISemantics() async throws {
        let recorder = RuntimeMessageRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(
            recorder,
            name: DiscordCSSComposer.messageHandlerName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                (() => {
                  Object.defineProperty(window, 'Notification', {
                    configurable: true,
                    writable: true,
                    value: undefined
                  });
                  window.fixtureMissingPermissionCallback = null;
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: DiscordCSSComposer.notificationBridgeUserScriptSource(
                    isEnabled: false
                ),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Missing Notification API fixture loaded")
        let navigationWaiter = RuntimeNavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = navigationWaiter
        webView.loadHTMLString(
            "<!doctype html><html><body></body></html>",
            baseURL: URL(string: "https://discord.com/app")!
        )
        await fulfillment(of: [loaded], timeout: 5)

        let disabledState = try await webView.evaluateJavaScript(
            """
            (() => {
              const DiscordNotification = Notification;
              window.fixtureMissingDiscordNotification = DiscordNotification;
              let errorName = null;
              try {
                new DiscordNotification('disabled notification');
              } catch (error) {
                errorName = error.name;
              }
              DiscordNotification.requestPermission(permission => {
                window.fixtureMissingPermissionCallback = permission;
              });
              const bridge = window['\(DiscordCSSComposer.notificationBridgeKey)'];
              return {
                notificationType: typeof DiscordNotification,
                permission: DiscordNotification.permission,
                requestPermissionType:
                  typeof DiscordNotification.requestPermission,
                errorName,
                originalNotificationIsNull:
                  bridge.originalNotification === null
              };
            })()
            """
        ) as! [String: Any]
        try await waitForRuntime()
        let disabledCallback = try await webView.evaluateJavaScript(
            "window.fixtureMissingPermissionCallback"
        ) as! String

        XCTAssertEqual(disabledState["notificationType"] as? String, "function")
        XCTAssertEqual(disabledState["permission"] as? String, "default")
        XCTAssertEqual(disabledState["requestPermissionType"] as? String, "function")
        XCTAssertEqual(disabledState["errorName"] as? String, "NotAllowedError")
        XCTAssertEqual(disabledState["originalNotificationIsNull"] as? Bool, true)
        XCTAssertEqual(disabledCallback, "default")
        XCTAssertTrue(recorder.notificationPayloads.isEmpty)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.notificationBridgeUserScriptSource(isEnabled: true)
        )
        let enabledState = try await webView.evaluateJavaScript(
            """
            (() => {
              const DiscordNotification = window.fixtureMissingDiscordNotification;
              const instance = new DiscordNotification(
                'private missing-API title',
                { body: 'private missing-API body' }
              );
              instance.close();
              return {
                permission: DiscordNotification.permission,
                cachedConstructorPreserved: DiscordNotification === Notification
              };
            })()
            """
        ) as! [String: Any]
        try await waitForRuntime()

        XCTAssertEqual(enabledState["permission"] as? String, "granted")
        XCTAssertEqual(enabledState["cachedConstructorPreserved"] as? Bool, true)
        XCTAssertEqual(recorder.notificationPayloads.count, 1)
        XCTAssertEqual(Set(recorder.notificationPayloads[0].keys), ["type"])

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.notificationBridgeUserScriptSource(isEnabled: false)
        )
        let permissionAfterDisabling = try await webView.evaluateJavaScript(
            "window.fixtureMissingDiscordNotification.permission"
        ) as! String
        XCTAssertEqual(permissionAfterDisabling, "default")
        XCTAssertEqual(recorder.notificationPayloads.count, 1)
        _ = navigationWaiter
    }

    func testNotificationBridgeInstallsOnRealWKWebViewNotificationSurface() async throws {
        let recorder = RuntimeMessageRecorder()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(
            recorder,
            name: DiscordCSSComposer.messageHandlerName
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: """
                (() => {
                  window.fixturePreBridgeNotificationType = typeof window.Notification;
                  window.fixturePreBridgeNotificationPermission =
                    typeof window.Notification?.permission === 'string'
                      ? window.Notification.permission
                      : 'unavailable';
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: DiscordCSSComposer.notificationBridgeUserScriptSource(),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        let loaded = expectation(description: "Real WK notification surface loaded")
        let navigationWaiter = RuntimeNavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = navigationWaiter
        webView.loadHTMLString(
            "<!doctype html><html><body></body></html>",
            baseURL: URL(string: "https://discord.com/app")!
        )
        await fulfillment(of: [loaded], timeout: 5)

        let state = try await webView.evaluateJavaScript(
            """
            (() => {
              const bridge = window['\(DiscordCSSComposer.notificationBridgeKey)'];
              const instance = new Notification(
                'private WK title',
                { body: 'private WK body' }
              );
              instance.close();
              return {
                notificationType: typeof Notification,
                permission: Notification.permission,
                captures: bridge.capturesPageNotifications,
                usesVirtualPermission: bridge.usesVirtualPermission,
                preBridgeType: window.fixturePreBridgeNotificationType,
                preBridgePermission: window.fixturePreBridgeNotificationPermission,
                bridgeOriginalPermission: bridge.originalPermission,
                originalNotificationIsNull: bridge.originalNotification === null
              };
            })()
            """
        ) as! [String: Any]
        try await waitForRuntime()

        XCTAssertEqual(state["notificationType"] as? String, "function")
        XCTAssertEqual(state["permission"] as? String, "granted")
        XCTAssertEqual(state["captures"] as? Bool, true)
        XCTAssertEqual(state["usesVirtualPermission"] as? Bool, true)
        XCTAssertEqual(
            state["bridgeOriginalPermission"] as? String,
            state["preBridgePermission"] as? String
        )
        XCTAssertEqual(
            state["originalNotificationIsNull"] as? Bool,
            state["preBridgeType"] as? String != "function"
        )
        XCTAssertEqual(recorder.notificationPayloads.count, 1)
        XCTAssertEqual(Set(recorder.notificationPayloads[0].keys), ["type"])
        _ = navigationWaiter
    }

    func testMessageActivityBridgeIgnoresBaselineAndHistoryButReportsRepeatedAppends() async throws {
        let recorder = RuntimeMessageRecorder()
        let (webView, navigationWaiter) = try await loadFixture(messageRecorder: recorder)
        _ = navigationWaiter

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const timeline = document.createElement('ol');
              timeline.id = 'message-timeline';
              timeline.setAttribute('data-list-id', 'chat-messages');
              const appendMessage = (id, text) => {
                const message = document.createElement('li');
                message.id = id;
                const content = document.createElement('span');
                content.textContent = text;
                message.append(content);
                timeline.append(message);
              };
              appendMessage('chat-messages-1-100', 'historical private text');
              appendMessage('chat-messages-1-101', 'latest private text');
              document.getElementById('messages').prepend(timeline);
            })()
            """
        )
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.userScriptSource(
                css: try runtimeCSS(customCSS: ""),
                configuration: makeConfiguration(navigation: .docked, composer: .full)
            )
        )

        // The initial timeline must remain quiet long enough to become the
        // runtime's history baseline.
        let messageTrackingIsArmed = try await waitForMessageTracking(in: webView)
        XCTAssertTrue(messageTrackingIsArmed)
        XCTAssertTrue(recorder.notificationPayloads.isEmpty)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const older = document.createElement('li');
              older.id = 'chat-messages-1-99';
              older.textContent = 'older private history';
              document.getElementById('message-timeline').prepend(older);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertTrue(recorder.notificationPayloads.isEmpty)

        _ = try await webView.evaluateJavaScript(
            """
            document.querySelector('#chat-messages-1-101 span')
              .append(document.createElement('button'))
            """
        )
        try await waitForRuntime()
        XCTAssertTrue(recorder.notificationPayloads.isEmpty)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const ordinary = document.createElement('li');
              ordinary.id = 'chat-messages-1-102';
              ordinary.textContent = 'ordinary non-notifying message';
              document.getElementById('message-timeline').append(ordinary);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertTrue(recorder.notificationPayloads.isEmpty)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const incoming = document.createElement('li');
              incoming.id = 'chat-messages-1-103';
              incoming.className = 'mentioned_fixture';
              incoming.textContent = 'new private message';
              document.getElementById('message-timeline').append(incoming);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 1)
        let firstPayload = try XCTUnwrap(recorder.notificationPayloads.first)
        XCTAssertEqual(Set(firstPayload.keys), ["type"])

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const repeated = document.createElement('li');
              repeated.setAttribute('data-list-item-id', 'chat-messages___1_104');
              repeated.className = 'mentioned_fixture';
              repeated.textContent = 'another private message';
              document.getElementById('message-timeline').append(repeated);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 2)
        let lastPayload = try XCTUnwrap(recorder.notificationPayloads.last)
        XCTAssertEqual(Set(lastPayload.keys), ["type"])

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const existing = document.querySelector(
                '[data-list-item-id="chat-messages___1_104"]'
              );
              existing.replaceWith(existing.cloneNode(true));
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 2)

        _ = try await webView.evaluateJavaScript(
            """
            document.querySelector('[data-list-item-id="chat-messages___1_104"]')
              .setAttribute('data-list-item-id', 'chat-messages___1_105')
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 3)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const channel = document.getElementById('channel');
              channel.setAttribute('aria-current', 'page');
              channel.className = 'modeMuted_fixture';
              const mutedMessage = document.createElement('li');
              mutedMessage.id = 'chat-messages-1-106';
              mutedMessage.className = 'mentioned_fixture';
              document.getElementById('message-timeline').append(mutedMessage);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 3)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              document.getElementById('channel').className = '';
              const unmutedMessage = document.createElement('li');
              unmutedMessage.id = 'chat-messages-1-107';
              unmutedMessage.className = 'mentioned_fixture';
              document.getElementById('message-timeline').append(unmutedMessage);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 4)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const timeline = document.getElementById('message-timeline');
              const message = id => {
                const element = document.createElement('li');
                element.id = id;
                return element;
              };
              timeline.replaceChildren(
                message('chat-messages-2-200'),
                message('chat-messages-2-201')
              );
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 4)
    }

    func testMessageFallbackDefersToTheLiveNotificationBridge() async throws {
        let recorder = RuntimeMessageRecorder()
        let (webView, navigationWaiter) = try await loadFixture(
            messageRecorder: recorder,
            notificationBridgeEnabled: true
        )
        _ = navigationWaiter

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const timeline = document.createElement('ol');
              timeline.id = 'message-timeline';
              timeline.setAttribute('data-list-id', 'chat-messages');
              const baseline = document.createElement('li');
              baseline.id = 'chat-messages-1-100';
              timeline.append(baseline);
              document.getElementById('messages').prepend(timeline);
            })()
            """
        )
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.userScriptSource(
                css: try runtimeCSS(customCSS: ""),
                configuration: makeConfiguration(navigation: .docked, composer: .full)
            )
        )
        let messageTrackingIsArmed = try await waitForMessageTracking(in: webView)
        XCTAssertTrue(messageTrackingIsArmed)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const message = document.createElement('li');
              message.id = 'chat-messages-1-101';
              message.className = 'mentioned_fixture';
              document.getElementById('message-timeline').append(message);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertTrue(recorder.notificationPayloads.isEmpty)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.notificationBridgeUserScriptSource(isEnabled: false)
        )
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const message = document.createElement('li');
              message.id = 'chat-messages-1-102';
              message.className = 'mentioned_fixture';
              document.getElementById('message-timeline').append(message);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertTrue(recorder.notificationPayloads.isEmpty)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.notificationBridgeUserScriptSource(isEnabled: true)
        )
        let bridgeWasReplaced = try await webView.evaluateJavaScript(
            """
            (() => {
              window.Notification = function DiscordReplacementNotification() {};
              return window.Notification !==
                window['\(DiscordCSSComposer.notificationBridgeKey)'].notificationProxy;
            })()
            """
        ) as! Bool
        XCTAssertTrue(bridgeWasReplaced)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const message = document.createElement('li');
              message.id = 'chat-messages-1-103';
              message.className = 'mentioned_fixture';
              document.getElementById('message-timeline').append(message);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 1)
        XCTAssertEqual(Set(recorder.notificationPayloads[0].keys), ["type"])
    }

    func testFloatingRailBridgeUsesLiveDiscordNodesAndSurvivesRerenders() async throws {
        let recorder = RuntimeMessageRecorder()
        let (webView, navigationWaiter) = try await loadFixture(messageRecorder: recorder)
        _ = navigationWaiter
        let configuration = makeConfiguration(
            navigation: .floating,
            composer: .essential,
            theme: .soft,
            accent: .pink,
            intensity: 0.7,
            colorScheme: .dark
        )
        let source = DiscordCSSComposer.userScriptSource(
            css: try runtimeCSS(customCSS: ""),
            configuration: configuration
        )

        _ = try await webView.evaluateJavaScript(source)
        try await waitForRuntime()

        let initialState = try await webView.evaluateJavaScript(
            """
            ({
              guildRole: document.getElementById('guilds').dataset.sidecordRole,
              channelRole: document.getElementById('channels').dataset.sidecordRole,
              accountRole: document.getElementById('account').dataset.sidecordRole,
              originalGuildCount: document.querySelectorAll('#guilds').length,
              guildDisplay: getComputedStyle(document.getElementById('guilds')).display,
              messageLeft: document.getElementById('messages').getBoundingClientRect().left,
              navigationLayoutCount: document.querySelectorAll(
                '[data-sidecord-role="navigation-layout"], ' +
                '[data-sidecord-role="main-surface"], ' +
                '[data-sidecord-navigation-ancestor]'
              ).length,
              navigation: document.documentElement.dataset.sidecordNavigation,
              theme: document.documentElement.dataset.sidecordTheme,
              accent: document.documentElement.dataset.sidecordAccent,
              scheme: document.documentElement.dataset.sidecordResolvedColorScheme,
              intensity: document.documentElement.style.getPropertyValue('--sidecord-theme-intensity')
            })
            """
        ) as! [String: Any]
        XCTAssertEqual(initialState["guildRole"] as? String, "guild-rail")
        XCTAssertEqual(initialState["channelRole"] as? String, "channel-list")
        XCTAssertEqual(initialState["accountRole"] as? String, "account-dock")
        XCTAssertEqual(initialState["originalGuildCount"] as? Int, 1)
        XCTAssertEqual(initialState["guildDisplay"] as? String, "none")
        XCTAssertEqual(initialState["messageLeft"] as! Double, 0, accuracy: 0.5)
        XCTAssertEqual(initialState["navigationLayoutCount"] as? Int, 0)
        XCTAssertEqual(initialState["navigation"] as? String, "floating")
        XCTAssertEqual(initialState["theme"] as? String, "soft")
        XCTAssertEqual(initialState["accent"] as? String, "pink")
        XCTAssertEqual(initialState["scheme"] as? String, "dark")
        XCTAssertEqual(initialState["intensity"] as? String, "0.700")

        let initialRailItems = try XCTUnwrap(recorder.latestRailItems)
        XCTAssertEqual(initialRailItems.count, 3)
        XCTAssertEqual(initialRailItems[0]["id"] as? String, "direct-messages")
        XCTAssertEqual(initialRailItems[0]["kind"] as? String, "directMessages")
        XCTAssertEqual(initialRailItems[1]["id"] as? String, "server:1")
        XCTAssertEqual(initialRailItems[1]["title"] as? String, "Fixture Server")
        XCTAssertEqual(initialRailItems[1]["selected"] as? Bool, true)
        XCTAssertEqual(initialRailItems[1]["unread"] as? Bool, true)
        XCTAssertEqual(initialRailItems[1]["mentions"] as? Int, 3)
        XCTAssertEqual(initialRailItems[2]["id"] as? String, "action:create-server")

        let drawerGeometryIsReserved = try await webView.evaluateJavaScript(
            """
            (() => {
              const channels = document.getElementById('channels').getBoundingClientRect();
              const account = document.getElementById('account').getBoundingClientRect();
              return channels.bottom <= account.top;
            })()
            """
        ) as! Bool
        XCTAssertTrue(drawerGeometryIsReserved)

        let activationResult = try await webView.evaluateJavaScript(
            DiscordCSSComposer.railActivationSource(id: "server:1")
        ) as! Bool
        XCTAssertTrue(activationResult)
        try await waitForRuntime()
        var drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertTrue(drawerOpen)
        let activationCount = try await webView.evaluateJavaScript(
            "window.fixtureServerActivationCount"
        ) as! Int
        XCTAssertEqual(activationCount, 1)

        let drawerGeometry = try await webView.evaluateJavaScript(
            "document.getElementById('channels').getBoundingClientRect().left"
        ) as! Double
        XCTAssertEqual(drawerGeometry, 12, accuracy: 0.5)

        _ = try await webView.evaluateJavaScript("document.getElementById('channel').click()")
        try await waitForRuntime()
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertFalse(drawerOpen)

        _ = try await webView.evaluateJavaScript("document.getElementById('add-server').click()")
        try await waitForRuntime()
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertFalse(drawerOpen)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.runtimeActionSource("openDrawer")
        )
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertTrue(drawerOpen)
        _ = try await webView.evaluateJavaScript(
            """
            document.getElementById('messages').dispatchEvent(
              new PointerEvent('pointerdown', { bubbles: true })
            )
            """
        )
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertFalse(drawerOpen)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.runtimeActionSource("openDrawer")
        )
        _ = try await webView.evaluateJavaScript(
            "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))"
        )
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertFalse(drawerOpen)

        _ = try await webView.evaluateJavaScript(
            """
            document.getElementById('guilds').outerHTML = `
              <nav id="guilds-v2" class="guilds_rerendered">
                <a id="server-v2" href="/channels/2/20"
                   data-list-item-id="guildsnav___2"
                   aria-label="Server two">Server two</a>
              </nav>`;
            document.getElementById('channels').outerHTML = `
              <nav id="channels-v2" class="sidebarList_rerendered">
                <a id="channel-v2" href="#/channels/2/21">Channel two</a>
              </nav>`;
            """
        )
        try await waitForRuntime()

        let rerendered = try await webView.evaluateJavaScript(
            """
            document.getElementById('guilds-v2').dataset.sidecordRole === 'guild-rail' &&
            document.getElementById('channels-v2').dataset.sidecordRole === 'channel-list' &&
            !document.getElementById('guilds') && !document.getElementById('channels')
            """
        ) as! Bool
        XCTAssertTrue(rerendered)
        XCTAssertEqual(recorder.latestRailItems?.count, 1)
        XCTAssertEqual(recorder.latestRailItems?.first?["id"] as? String, "server:2")
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.railActivationSource(id: "server:2")
        )
        try await waitForRuntime()
        drawerOpen = try await drawerIsOpen(in: webView)
        XCTAssertTrue(drawerOpen)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.userScriptSource(
                css: try runtimeCSS(customCSS: ""),
                configuration: makeConfiguration(navigation: .hidden, composer: .essential)
            )
        )
        try await waitForRuntime()
        let modeChangeClosedDrawer = try await webView.evaluateJavaScript(
            """
            document.documentElement.dataset.sidecordNavigation === 'hidden' &&
            !document.documentElement.hasAttribute('data-sidecord-drawer-open')
            """
        ) as! Bool
        XCTAssertTrue(modeChangeClosedDrawer)
    }

    func testComposerEssentialRetainsCoreControlsAndModeChangesInPlace() async throws {
        let (webView, navigationWaiter) = try await loadFixture()
        _ = navigationWaiter
        let essential = makeConfiguration(navigation: .floating, composer: .essential)
        let source = DiscordCSSComposer.userScriptSource(
            css: try runtimeCSS(customCSS: ""),
            configuration: essential
        )
        _ = try await webView.evaluateJavaScript(source)
        try await waitForRuntime()

        let essentialVisibility = try await controlVisibility(in: webView)
        XCTAssertNotEqual(essentialVisibility["attachment"], "none")
        XCTAssertNotEqual(essentialVisibility["gif"], "none")
        XCTAssertNotEqual(essentialVisibility["emoji"], "none")
        XCTAssertEqual(essentialVisibility["gift"], "none")
        XCTAssertEqual(essentialVisibility["sticker"], "none")
        XCTAssertEqual(essentialVisibility["apps"], "none")

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.userScriptSource(
                css: try runtimeCSS(customCSS: ""),
                configuration: makeConfiguration(navigation: .docked, composer: .full)
            )
        )
        try await waitForRuntime()

        let fullVisibility = try await controlVisibility(in: webView)
        for control in ["attachment", "gif", "emoji", "gift", "sticker", "apps"] {
            XCTAssertNotEqual(fullVisibility[control], "none", control)
        }
        let runtimeStillExists = try await webView.evaluateJavaScript(
            "window['\(DiscordCSSComposer.runtimeKey)']?.version === 6"
        ) as! Bool
        XCTAssertTrue(runtimeStillExists)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.userScriptSource(
                css: try runtimeCSS(customCSS: ""),
                configuration: makeConfiguration(navigation: .hidden, composer: .hidden)
            )
        )
        try await waitForRuntime()
        let hiddenState = try await webView.evaluateJavaScript(
            """
            ({
              guild: getComputedStyle(document.getElementById('guilds')).display,
              channels: getComputedStyle(document.getElementById('channels')).display,
              composer: getComputedStyle(document.getElementById('composer-form')).display,
              drawer: document.documentElement.hasAttribute('data-sidecord-drawer-open')
            })
            """
        ) as! [String: Any]
        XCTAssertEqual(hiddenState["guild"] as? String, "none")
        XCTAssertEqual(hiddenState["channels"] as? String, "none")
        XCTAssertEqual(hiddenState["composer"] as? String, "none")
        XCTAssertEqual(hiddenState["drawer"] as? Bool, false)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.runtimeActionSource("openDrawer")
        )
        try await waitForRuntime()
        let transientReveal = try await webView.evaluateJavaScript(
            """
            document.documentElement.dataset.sidecordNavigation === 'floating' &&
            document.documentElement.hasAttribute('data-sidecord-drawer-open') &&
            getComputedStyle(document.getElementById('guilds')).display === 'none' &&
            getComputedStyle(document.getElementById('channels')).display !== 'none'
            """
        ) as! Bool
        XCTAssertTrue(transientReveal)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.runtimeActionSource("closeDrawer")
        )
        try await waitForRuntime()
        let returnedToHidden = try await webView.evaluateJavaScript(
            """
            document.documentElement.dataset.sidecordNavigation === 'hidden' &&
            !document.documentElement.hasAttribute('data-sidecord-drawer-open')
            """
        ) as! Bool
        XCTAssertTrue(returnedToHidden)
    }

    func testThemeStateSelfHealsAndCustomCSSIsLast() async throws {
        let (webView, navigationWaiter) = try await loadFixture()
        _ = navigationWaiter
        let customCSS = "body { --sidecord-precedence-check: custom; }"
        let css = try runtimeCSS(customCSS: customCSS)
        XCTAssertTrue(css.hasSuffix(customCSS))

        let source = DiscordCSSComposer.userScriptSource(
            css: css,
            configuration: makeConfiguration(
                navigation: .docked,
                composer: .full,
                theme: .oled,
                accent: .green,
                intensity: 0.45,
                colorScheme: .light
            )
        )
        _ = try await webView.evaluateJavaScript(source)
        try await waitForRuntime()

        let initial = try await webView.evaluateJavaScript(
            """
            ({
              theme: document.documentElement.dataset.sidecordTheme,
              accent: document.documentElement.dataset.sidecordAccent,
              requested: document.documentElement.dataset.sidecordColorScheme,
              resolved: document.documentElement.dataset.sidecordResolvedColorScheme,
              intensity: document.documentElement.style.getPropertyValue('--sidecord-theme-intensity'),
              strength: document.documentElement.style.getPropertyValue('--sidecord-theme-strength'),
              custom: getComputedStyle(document.body).getPropertyValue('--sidecord-precedence-check').trim()
            })
            """
        ) as! [String: Any]
        XCTAssertEqual(initial["theme"] as? String, "oled")
        XCTAssertEqual(initial["accent"] as? String, "green")
        XCTAssertEqual(initial["requested"] as? String, "light")
        XCTAssertEqual(initial["resolved"] as? String, "light")
        XCTAssertEqual(initial["intensity"] as? String, "0.450")
        XCTAssertEqual(initial["strength"] as? String, "45.000%")
        XCTAssertEqual(initial["custom"] as? String, "custom")

        _ = try await webView.evaluateJavaScript(
            """
            document.documentElement.removeAttribute('data-sidecord-theme');
            document.documentElement.style.removeProperty('--sidecord-theme-intensity');
            document.getElementById('\(DiscordCSSComposer.styleElementID)').remove();
            """
        )
        try await waitForRuntime()

        let repaired = try await webView.evaluateJavaScript(
            """
            document.documentElement.dataset.sidecordTheme === 'oled' &&
            document.documentElement.style.getPropertyValue('--sidecord-theme-intensity') === '0.450' &&
            !!document.getElementById('\(DiscordCSSComposer.styleElementID)')
            """
        ) as! Bool
        XCTAssertTrue(repaired)
    }

    func testCuratedThemeOverridesNestedDiscordScopesAndRestoresNativeTheme() async throws {
        let (webView, navigationWaiter) = try await loadFixture()
        _ = navigationWaiter
        _ = try await webView.evaluateJavaScript(
            """
            const nativeTheme = document.createElement('style');
            nativeTheme.textContent = `
              .theme-midnight.chat_fixture {
                --background-primary: rgb(1, 2, 3) !important;
                --channeltextarea-background: rgb(7, 8, 9) !important;
                --text-normal: rgb(245, 245, 245) !important;
                background-color: rgb(1, 2, 3);
                color: rgb(245, 245, 245);
              }
              .theme-light.chat_fixture {
                --background-primary: rgb(248, 249, 250) !important;
                --channeltextarea-background: rgb(240, 241, 242) !important;
                --text-normal: rgb(20, 21, 22) !important;
                background-color: rgb(248, 249, 250);
                color: rgb(20, 21, 22);
              }
              .sidebarList_fixture { background-color: rgb(4, 5, 6); }
              .channelTextArea_fixture { background-color: rgb(7, 8, 9); }
            `;
            document.head.appendChild(nativeTheme);
            document.getElementById('messages').className = 'theme-midnight chat_fixture';
            """
        )

        let css = try runtimeCSS(customCSS: "")
        let lightSource = DiscordCSSComposer.userScriptSource(
            css: css,
            configuration: makeConfiguration(
                navigation: .docked,
                composer: .full,
                theme: .soft,
                accent: .pink,
                intensity: 1,
                colorScheme: .light
            )
        )
        _ = try await webView.evaluateJavaScript(lightSource)
        try await waitForRuntime()

        let lightState = try await themeFixtureState(in: webView)
        XCTAssertEqual(lightState["scope"] as? String, "light")
        XCTAssertEqual(lightState["resolved"] as? String, "light")
        XCTAssertEqual(lightState["midnight"] as? Bool, true)
        XCTAssertEqual(lightState["forcedLightClass"] as? Bool, false)
        XCTAssertNotEqual(lightState["chatBackground"] as? String, "rgb(1, 2, 3)")
        XCTAssertNotEqual(lightState["sidebarBackground"] as? String, "rgb(4, 5, 6)")
        XCTAssertNotEqual(lightState["composerBackground"] as? String, "rgb(7, 8, 9)")
        XCTAssertNotEqual(lightState["chatText"] as? String, "rgb(245, 245, 245)")
        XCTAssertFalse((lightState["semanticBackground"] as? String ?? "").isEmpty)
        XCTAssertFalse((lightState["modernBackground"] as? String ?? "").isEmpty)

        _ = try await webView.evaluateJavaScript(
            """
            const oldMessages = document.getElementById('messages');
            const replacement = oldMessages.cloneNode(true);
            oldMessages.replaceWith(replacement);
            """
        )
        try await waitForRuntime()
        let replacementScope = try await webView.evaluateJavaScript(
            "document.getElementById('messages').dataset.sidecordThemeScope"
        ) as? String
        XCTAssertEqual(replacementScope, "light")

        _ = try await webView.evaluateJavaScript(
            "document.getElementById('messages').className = 'theme-light chat_fixture'"
        )
        let darkSource = DiscordCSSComposer.userScriptSource(
            css: css,
            configuration: makeConfiguration(
                navigation: .docked,
                composer: .full,
                theme: .oled,
                accent: .purple,
                intensity: 1,
                colorScheme: .dark
            )
        )
        _ = try await webView.evaluateJavaScript(darkSource)
        try await waitForRuntime()
        let darkState = try await themeFixtureState(in: webView)
        XCTAssertEqual(darkState["scope"] as? String, "dark")
        XCTAssertEqual(darkState["resolved"] as? String, "dark")
        XCTAssertEqual(darkState["nativeLight"] as? Bool, true)
        XCTAssertEqual(darkState["forcedDarkClass"] as? Bool, false)
        XCTAssertNotEqual(darkState["chatBackground"] as? String, "rgb(248, 249, 250)")

        let nativeSource = DiscordCSSComposer.userScriptSource(
            css: css,
            configuration: makeConfiguration(
                navigation: .docked,
                composer: .full,
                theme: .discord,
                colorScheme: .system
            )
        )
        _ = try await webView.evaluateJavaScript(nativeSource)
        try await waitForRuntime()
        let nativeState = try await themeFixtureState(in: webView)
        XCTAssertEqual(nativeState["hasScope"] as? Bool, false)
        XCTAssertEqual(nativeState["nativeLight"] as? Bool, true)
        XCTAssertEqual(nativeState["forcedDarkClass"] as? Bool, false)
        XCTAssertEqual(nativeState["chatBackground"] as? String, "rgb(248, 249, 250)")
    }

    func testNarrowLoginKeepsDiscordQRCodeVisibleAndReachable() async throws {
        let (webView, navigationWaiter) = try await loadFixture(
            html: Self.loginFixtureHTML,
            frame: CGRect(x: 0, y: 0, width: 420, height: 700)
        )
        _ = navigationWaiter
        let source = DiscordCSSComposer.userScriptSource(
            css: try runtimeCSS(customCSS: ""),
            configuration: makeConfiguration(navigation: .docked, composer: .full)
        )

        _ = try await webView.evaluateJavaScript(source)
        try await waitForRuntime()

        let state = try await webView.evaluateJavaScript(
            """
            (() => {
              const auth = document.getElementById('auth');
              const stack = document.getElementById('login-stack');
              const qr = document.getElementById('qr-login');
              const rect = qr.getBoundingClientRect();
              return {
                innerWidth,
                display: getComputedStyle(qr).display,
                direction: getComputedStyle(stack).flexDirection,
                width: rect.width,
                height: rect.height,
                fitsHorizontally: rect.left >= auth.getBoundingClientRect().left &&
                  rect.right <= auth.getBoundingClientRect().right,
                scrollReachable: auth.scrollHeight >= rect.bottom - auth.getBoundingClientRect().top
              };
            })()
            """
        ) as! [String: Any]

        XCTAssertEqual(state["innerWidth"] as? Int, 420)
        XCTAssertNotEqual(state["display"] as? String, "none")
        XCTAssertEqual(state["direction"] as? String, "column")
        XCTAssertGreaterThan(state["width"] as! Double, 0)
        XCTAssertGreaterThan(state["height"] as! Double, 0)
        XCTAssertEqual(state["fitsHorizontally"] as? Bool, true)
        XCTAssertEqual(state["scrollReachable"] as? Bool, true)
    }

    func testVisualThemeSheetContainsNoLayoutOrVisibilityDeclarations() throws {
        let css = try resource(named: "visual-themes")
        let forbiddenDeclaration = #"(?im)^\s*(display|position|top|right|bottom|left|inset|width|min-width|max-width|height|min-height|max-height|margin|padding|transform|visibility|overflow|pointer-events|z-index)\s*:"#
        XCTAssertNil(css.range(of: forbiddenDeclaration, options: .regularExpression))
        XCTAssertTrue(css.contains("data-sidecord-resolved-color-scheme=\"dark\""))
        XCTAssertTrue(css.contains("data-sidecord-resolved-color-scheme=\"light\""))
        XCTAssertTrue(css.contains("data-sidecord-theme=\"discord\"][data-sidecord-color-scheme=\"dark\"]"))
        XCTAssertTrue(css.contains("data-sidecord-theme=\"discord\"][data-sidecord-color-scheme=\"light\"]"))
        XCTAssertFalse(css.contains("data-sidecord-theme=\"discord\"][data-sidecord-color-scheme=\"system\"]"))
        XCTAssertTrue(css.contains("--text-normal:"))
        XCTAssertTrue(css.contains("--interactive-normal:"))
        XCTAssertTrue(css.contains("--channels-default:"))
        XCTAssertTrue(css.contains("--background-primary:"))
        XCTAssertTrue(css.contains("--background-base-lowest:"))
        XCTAssertTrue(css.contains("--background-surface-highest:"))
        XCTAssertTrue(css.contains("--bg-surface-overlay:"))
        XCTAssertTrue(css.contains("--channeltextarea-background:"))
        XCTAssertTrue(css.contains("--modal-background:"))
        XCTAssertTrue(css.contains("--scrollbar-auto-thumb:"))
        XCTAssertTrue(css.contains("data-sidecord-theme-scope=\"dark\""))
        XCTAssertTrue(css.contains("data-sidecord-theme-scope=\"light\""))
    }

    private func makeConfiguration(
        navigation: DiscordNavigationPresentation,
        composer: DiscordComposerMode,
        theme: DiscordVisualTheme = .discord,
        accent: SideCordAccent = .automatic,
        intensity: Double = 1,
        colorScheme: ThemeColorScheme = .system
    ) -> DiscordCSSRuntimeConfiguration {
        DiscordCSSComposer.runtimeConfiguration(
            layoutOptions: DiscordLayoutOptions(
                navigationPresentation: navigation,
                composerMode: composer
            ),
            visualTheme: theme,
            themeAccent: accent,
            themeIntensity: intensity,
            themeColorScheme: colorScheme
        )
    }

    private func runtimeCSS(customCSS: String) throws -> String {
        DiscordCSSComposer.compose(
            preset: .standard,
            compactPresetCSS: "",
            layoutModifiersCSS: try resource(named: "layout-mods"),
            visualThemesCSS: try resource(named: "visual-themes"),
            layoutOptions: .focus,
            customCSS: customCSS,
            customCSSEnabled: !customCSS.isEmpty
        )
    }

    private func resource(named name: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("SideCord/Resources/\(name).css"),
            encoding: .utf8
        )
    }

    private func loadFixture(
        messageRecorder: RuntimeMessageRecorder? = nil,
        html: String? = nil,
        frame: CGRect = CGRect(x: 0, y: 0, width: 800, height: 700),
        notificationBridgeEnabled: Bool? = nil
    ) async throws -> (WKWebView, RuntimeNavigationWaiter) {
        let configuration = WKWebViewConfiguration()
        if let messageRecorder {
            configuration.userContentController.add(
                messageRecorder,
                name: DiscordCSSComposer.messageHandlerName
            )
        }
        if let notificationBridgeEnabled {
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: DiscordCSSComposer.notificationBridgeUserScriptSource(
                        isEnabled: notificationBridgeEnabled
                    ),
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: true
                )
            )
        }
        let webView = WKWebView(
            frame: frame,
            configuration: configuration
        )
        let loaded = expectation(description: "Local Discord fixture loaded")
        let navigationWaiter = RuntimeNavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = navigationWaiter
        webView.loadHTMLString(
            html ?? Self.fixtureHTML,
            baseURL: URL(string: "https://discord.com/app")!
        )
        await fulfillment(of: [loaded], timeout: 5)
        return (webView, navigationWaiter)
    }

    private func drawerIsOpen(in webView: WKWebView) async throws -> Bool {
        try await webView.evaluateJavaScript(
            "document.documentElement.hasAttribute('data-sidecord-drawer-open')"
        ) as! Bool
    }

    private func controlVisibility(in webView: WKWebView) async throws -> [String: String] {
        try await webView.evaluateJavaScript(
            """
            Object.fromEntries(
              ['attachment', 'gif', 'emoji', 'gift', 'sticker', 'apps'].map(id =>
                [id, getComputedStyle(document.getElementById(id)).display]
              )
            )
            """
        ) as! [String: String]
    }

    private func themeFixtureState(in webView: WKWebView) async throws -> [String: Any] {
        try await webView.evaluateJavaScript(
            """
            (() => {
              const chat = document.getElementById('messages');
              const sidebar = document.getElementById('channels');
              const composer = document.getElementById('composer');
              const chatStyle = getComputedStyle(chat);
              return {
                scope: chat.getAttribute('data-sidecord-theme-scope'),
                hasScope: chat.hasAttribute('data-sidecord-theme-scope'),
                resolved: document.documentElement.dataset.sidecordResolvedColorScheme,
                midnight: chat.classList.contains('theme-midnight'),
                nativeLight: chat.classList.contains('theme-light'),
                forcedLightClass: document.documentElement.classList.contains('theme-light'),
                forcedDarkClass: document.documentElement.classList.contains('theme-dark'),
                chatBackground: chatStyle.backgroundColor,
                sidebarBackground: getComputedStyle(sidebar).backgroundColor,
                composerBackground: getComputedStyle(composer).backgroundColor,
                chatText: chatStyle.color,
                semanticBackground: chatStyle.getPropertyValue('--background-primary').trim(),
                modernBackground: chatStyle.getPropertyValue('--background-base-low').trim()
              };
            })()
            """
        ) as! [String: Any]
    }

    private func waitForRuntime() async throws {
        try await Task.sleep(for: .milliseconds(120))
    }

    private func waitForNotificationCount(
        _ expectedCount: Int,
        recorder: RuntimeMessageRecorder
    ) async throws -> Bool {
        for _ in 0..<30 {
            if recorder.notificationPayloads.count >= expectedCount { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func waitForServiceWorkerNotificationBaseline(
        in webView: WKWebView
    ) async throws -> Bool {
        for _ in 0..<30 {
            let isBaselined = try await webView.evaluateJavaScript(
                "window['\(DiscordCSSComposer.notificationBridgeKey)']?.serviceWorkerNotificationsBaselined === true"
            ) as! Bool
            if isBaselined { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private func waitForMessageTracking(in webView: WKWebView) async throws -> Bool {
        for _ in 0..<40 {
            let isArmed = try await webView.evaluateJavaScript(
                "window['\(DiscordCSSComposer.runtimeKey)']?.messageTrackingArmed === true"
            ) as! Bool
            if isArmed { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private static let fixtureHTML = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <style>
          html, body { margin: 0; width: 100%; height: 100%; }
          #app-mount { display: flex; width: 100%; height: 100%; }
          #sidebar {
            display: flex;
            flex: 0 0 0;
            min-width: 0;
            height: 420px;
            overflow: hidden;
            transform: translate3d(0, 0, 0);
          }
          #guilds { flex: 0 0 72px; }
          #channels { flex: 0 0 240px; }
          #messages { flex: 1 1 auto; min-width: 0; }
        </style>
      </head>
      <body>
        <div id="app-mount">
          <aside id="sidebar">
            <nav id="guilds" class="guilds_fixture">
              <a id="home" href="/channels/@me"
                 data-list-item-id="guildsnav___home"
                 aria-label="Direct Messages">
                <img alt="Direct Messages"
                     src="data:image/png;base64,iVBORw0KGgo=">
              </a>
              <a id="server" href="/channels/1/10"
                 data-list-item-id="guildsnav___1"
                 aria-label="Fixture Server"
                 aria-selected="true"
                 class="selected_fixture unread_fixture">
                <img alt="Fixture Server"
                     src="https://cdn.discordapp.com/icons/1/example.png">
                <span class="numberBadge_fixture">3</span>
              </a>
              <button id="add-server" data-list-item-id="guildsnav___create-join-button">
                Add server
              </button>
            </nav>
            <nav id="channels" class="sidebarList_fixture">
              <a id="channel" href="#/channels/1/11">Channel</a>
            </nav>
            <section id="account" class="panels_fixture">Account and voice</section>
          </aside>
          <main id="messages">
            <form id="composer-form" class="form_fixture">
              <div id="composer" class="channelTextArea_fixture">
                <button id="attachment" aria-label="Upload a file">+</button>
                <button id="gif" aria-label="Open GIF picker">GIF</button>
                <button id="emoji" aria-label="Select emoji">Emoji</button>
                <button id="gift" aria-label="Send a gift">Gift</button>
                <button id="sticker" aria-label="Open sticker picker">Sticker</button>
                <div id="apps" class="channelAppLauncher_fixture">Apps</div>
              </div>
            </form>
          </main>
        </div>
        <script>
          window.fixtureServerActivationCount = 0;
          document.addEventListener('click', event => {
            if (event.target.closest('a')) event.preventDefault();
            if (event.target.closest('#server')) window.fixtureServerActivationCount += 1;
          });
        </script>
      </body>
    </html>
    """

    private static let loginFixtureHTML = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <style>
          html, body { margin: 0; width: 100%; height: 100%; }
          body { display: grid; place-items: center; }
          .authBox_fixture {
            box-sizing: border-box;
            max-height: 100vh;
            overflow-y: auto;
            padding: 16px;
            width: 784px;
          }
          .centeringWrapper_fixture { width: 100%; }
          #login-stack { display: flex; flex-direction: row; gap: 64px; }
          .mainLoginContainer_fixture { flex: 1 1 auto; min-width: 0; }
          .qrLogin_fixture {
            align-items: center;
            display: flex;
            flex-direction: column;
            height: 300px;
            width: 240px;
          }
          @media (max-width: 830px) {
            .authBoxExpanded_fixture { max-width: 480px; }
            .qrLogin_fixture { display: none; }
          }
        </style>
      </head>
      <body>
        <form id="auth" class="authBoxExpanded_fixture authBox_fixture">
          <div class="centeringWrapper_fixture">
            <div id="login-stack" data-direction="horizontal">
              <div class="mainLoginContainer_fixture">
                <label>Email <input id="email" type="text"></label>
                <label>Password <input id="password" type="password"></label>
              </div>
              <div id="qr-login" class="qrLogin_fixture">
                <div aria-label="QR code to log in">QR</div>
                <strong>Log in with QR Code</strong>
              </div>
            </div>
          </div>
        </form>
      </body>
    </html>
    """
}

@MainActor
private final class RuntimeMessageRecorder: NSObject, WKScriptMessageHandler {
    private(set) var messages: [[String: Any]] = []

    var latestRailItems: [[String: Any]]? {
        messages.reversed().first(where: { $0["type"] as? String == "rail" })?["items"]
            as? [[String: Any]]
    }

    var incomingCallStates: [Bool] {
        messages.compactMap { payload in
            guard payload["type"] as? String == "incomingCall" else { return nil }
            return payload["active"] as? Bool
        }
    }

    var notificationPayloads: [[String: Any]] {
        messages.filter { $0["type"] as? String == "notification" }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == DiscordCSSComposer.messageHandlerName,
              message.frameInfo.isMainFrame,
              let payload = message.body as? [String: Any]
        else { return }
        messages.append(payload)
    }
}

@MainActor
private final class RuntimeNavigationWaiter: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish()
    }
}
