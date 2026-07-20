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

    func testIncomingCallActionsStayScopedAndFailClosedWhenAmbiguous() async throws {
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
              window.fixtureAnswered = 0;
              window.fixtureDeclined = 0;
              const call = document.createElement('div');
              call.id = 'call-fixture';
              call.className = 'ringingIncoming_fixture';
              call.setAttribute('aria-label', 'Incoming call from Ada');
              call.style.cssText =
                'display: flex; align-items: center; gap: 12px; position: fixed; ' +
                'top: 20px; left: 20px; width: 260px; height: 90px';
              const answer = document.createElement('button');
              answer.type = 'button';
              answer.textContent = 'Answer';
              answer.setAttribute('aria-label', 'Answer call');
              answer.style.cssText =
                'display: block; flex: 0 0 96px; width: 96px; height: 36px; ' +
                'visibility: visible; opacity: 1';
              answer.addEventListener('click', () => window.fixtureAnswered++);
              const decline = document.createElement('button');
              decline.type = 'button';
              decline.textContent = 'Decline';
              decline.setAttribute('aria-label', 'Decline call');
              decline.style.cssText =
                'display: block; flex: 0 0 96px; width: 96px; height: 36px; ' +
                'visibility: visible; opacity: 1';
              decline.addEventListener('click', () => window.fixtureDeclined++);
              call.append(answer, decline);
              document.body.appendChild(call);

              const unrelated = document.createElement('button');
              unrelated.setAttribute('aria-label', 'Answer survey');
              unrelated.addEventListener('click', () => window.fixtureAnswered += 100);
              document.body.appendChild(unrelated);
            })()
            """
        )
        try await waitForRuntime()

        let answerResult = try await webView.evaluateJavaScript(
            DiscordCSSComposer.incomingCallActionSource("answer")
        ) as? Bool
        let declineResult = try await webView.evaluateJavaScript(
            DiscordCSSComposer.incomingCallActionSource("decline")
        ) as? Bool
        XCTAssertEqual(answerResult, true)
        XCTAssertEqual(declineResult, true)

        let counts = try await webView.evaluateJavaScript(
            "({ answered: window.fixtureAnswered, declined: window.fixtureDeclined })"
        ) as? [String: Int]
        XCTAssertEqual(counts?["answered"], 1)
        XCTAssertEqual(counts?["declined"], 1)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const duplicate = document.createElement('button');
              duplicate.type = 'button';
              duplicate.textContent = 'Accept';
              duplicate.setAttribute('aria-label', 'Accept incoming call');
              duplicate.style.cssText =
                'display: block; flex: 0 0 96px; width: 96px; height: 36px; ' +
                'visibility: visible; opacity: 1';
              document.getElementById('call-fixture').appendChild(duplicate);
            })()
            """
        )
        try await waitForRuntime()
        let ambiguousResult = try await webView.evaluateJavaScript(
            DiscordCSSComposer.incomingCallActionSource("answer")
        ) as? Bool
        XCTAssertEqual(ambiguousResult, false)
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

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              new Notification('rapid one');
              new Notification('rapid two');
              new Notification('rapid three');
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 5)
        XCTAssertTrue(recorder.notificationPayloads.allSatisfy { Set($0.keys) == ["type"] })

        _ = try await webView.evaluateJavaScript(
            "(() => { window.Notification = window.fixtureOriginalNotification; return true; })()"
        )
        try await Task.sleep(for: .milliseconds(400))
        _ = try await webView.evaluateJavaScript(
            "(() => { new Notification('repaired hook'); return true; })()"
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 6)

        _ = try await webView.evaluateJavaScript("document.title = '(1) Discord'")
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 7)
        XCTAssertTrue(recorder.notificationPayloads.allSatisfy { Set($0.keys) == ["type"] })
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

    func testNotificationBridgeReportsOnlyDiscordMessageAndMentionSounds() async throws {
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
                  window.fixtureMediaPlayCount = 0;
                  window.fixtureSoundpack = 'classic';
                  Object.defineProperty(HTMLMediaElement.prototype, 'play', {
                    configurable: true,
                    writable: true,
                    value() {
                      window.fixtureMediaPlayCount += 1;
                      return Promise.resolve();
                    }
                  });

                  window.fixtureSoundURLs = {
                    './message1.mp3':
                      'https://discord.com/assets/current-message.mp3?version=1',
                    './message2.mp3':
                      'https://discord.com/assets/current-message-two.mp3',
                    './mention1.mp3':
                      'https://discord.com/assets/current-mention.mp3',
                    './lofi_message1.mp3':
                      'https://discord.com/assets/current-lofi-message.mp3',
                    './discodo.mp3':
                      'https://discord.com/assets/current-discodo.mp3',
                    './mute.mp3':
                      'https://discord.com/assets/current-mute.mp3'
                  };
                  const factories = {
                    4242(module) {
                      const logicalSoundNames = [
                        './message1.mp3',
                        './message2.mp3',
                        './mention1.mp3',
                        './lofi_message1.mp3',
                        './discodo.mp3',
                        './mute.mp3'
                      ];
                      const context = key => window.fixtureSoundURLs[key];
                      context.keys = () => logicalSoundNames;
                      module.exports = context;
                    },
                    9001(module) {
                      const packs = {
                        classic: { message1: 'message1' },
                        discodo: { message1: 'discodo' }
                      };
                      module.exports = pack => packs[pack];
                    },
                    8001(module) {
                      const SoundpackStore = {
                        getSoundpack() {
                          return window.fixtureSoundpack;
                        }
                      };
                      module.exports = { A: SoundpackStore };
                    }
                  };
                  const cache = {};
                  const fixtureWebpackRequire = id => {
                    if (!cache[id]) {
                      const module = { exports: {} };
                      cache[id] = module;
                      factories[id](module);
                    }
                    return cache[id].exports;
                  };
                  fixtureWebpackRequire.m = factories;

                  const chunks = [];
                  chunks.push = function(payload) {
                    Array.prototype.push.call(this, payload);
                    payload[2]?.(fixtureWebpackRequire);
                    return this.length;
                  };
                  window.fixtureInstallWebpack = () => {
                    window.webpackChunkdiscord_app = chunks;
                  };
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
        let loaded = expectation(description: "Discord sound bridge fixture loaded")
        let navigationWaiter = RuntimeNavigationWaiter { loaded.fulfill() }
        webView.navigationDelegate = navigationWaiter
        webView.loadHTMLString(
            "<!doctype html><html><body></body></html>",
            baseURL: URL(string: "https://discord.com/app")!
        )
        await fulfillment(of: [loaded], timeout: 5)
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const bridge =
                window['\(DiscordCSSComposer.notificationBridgeKey)'];
              bridge.notificationSoundDiscoveryAttempts = 52;
              window.fixtureInstallWebpack();
              const audio = document.createElement('audio');
              audio.src = window.fixtureSoundURLs['./mute.mp3'];
              audio.play();
            })()
            """
        )
        let soundCaptureIsReady = try await waitForNotificationSoundCapture(
            in: webView
        )
        XCTAssertTrue(soundCaptureIsReady)
        XCTAssertTrue(recorder.notificationPayloads.isEmpty)
        _ = try await webView.evaluateJavaScript(
            "window.fixtureMediaPlayCount = 0"
        )

        let bridgeState = try await webView.evaluateJavaScript(
            """
            (() => {
              const bridge = window['\(DiscordCSSComposer.notificationBridgeKey)'];
              return {
                capturesNotificationSounds: bridge.capturesNotificationSounds,
                discoveredSoundCount: bridge.notificationSoundPaths.size,
                discodoSoundCount:
                  bridge.discodoNotificationSoundPaths.size,
                foundSoundpackStore:
                  typeof bridge.notificationSoundPackStore?.getSoundpack ===
                    'function',
                playIsWrapped:
                  HTMLMediaElement.prototype.play === bridge.mediaPlayProxy
              };
            })()
            """
        ) as! [String: Any]
        XCTAssertEqual(bridgeState["capturesNotificationSounds"] as? Bool, true)
        XCTAssertEqual(bridgeState["discoveredSoundCount"] as? Int, 5)
        XCTAssertEqual(bridgeState["discodoSoundCount"] as? Int, 1)
        XCTAssertEqual(bridgeState["foundSoundpackStore"] as? Bool, true)
        XCTAssertEqual(bridgeState["playIsWrapped"] as? Bool, true)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const play = source => {
                const audio = document.createElement('audio');
                audio.src = source;
                audio.play();
              };
              play(window.fixtureSoundURLs['./message1.mp3']);
              play(window.fixtureSoundURLs['./mention1.mp3']);
              play(window.fixtureSoundURLs['./lofi_message1.mp3']);
              play(window.fixtureSoundURLs['./discodo.mp3']);
              play(window.fixtureSoundURLs['./mute.mp3']);
              play('https://discord.com/assets/unrelated-media.mp3');
              return true;
            })()
            """
        )
        try await waitForRuntime()

        XCTAssertEqual(recorder.notificationPayloads.count, 3)
        for payload in recorder.notificationPayloads {
            XCTAssertEqual(Set(payload.keys), ["type"])
        }
        let playCount = try await webView.evaluateJavaScript(
            "window.fixtureMediaPlayCount"
        ) as! Int
        XCTAssertEqual(playCount, 6)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              window.fixtureSoundpack = 'discodo';
              const audio = document.createElement('audio');
              audio.src = window.fixtureSoundURLs['./discodo.mp3'];
              audio.play();
              return true;
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 4)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const bridge =
                window['\(DiscordCSSComposer.notificationBridgeKey)'];
              bridge.notificationSoundPackStore = null;
              const audio = document.createElement('audio');
              audio.src = window.fixtureSoundURLs['./discodo.mp3'];
              audio.play();
              return true;
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 5)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              new Notification('private delayed notification');
              setTimeout(() => {
                const audio = document.createElement('audio');
                audio.src = window.fixtureSoundURLs['./message1.mp3'];
                audio.play();
              }, 900);
              return true;
            })()
            """
        )
        try await Task.sleep(for: .milliseconds(1_100))
        XCTAssertEqual(recorder.notificationPayloads.count, 7)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.notificationBridgeUserScriptSource(isEnabled: false)
        )
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const audio = document.createElement('audio');
              audio.src = window.fixtureSoundURLs['./message2.mp3'];
              audio.play();
              return true;
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 7)
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
              ordinary.textContent = 'ordinary incoming message';
              document.getElementById('message-timeline').append(ordinary);
            })()
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 1)

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
        XCTAssertEqual(recorder.notificationPayloads.count, 2)
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
        XCTAssertEqual(recorder.notificationPayloads.count, 3)
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
        XCTAssertEqual(recorder.notificationPayloads.count, 3)

        _ = try await webView.evaluateJavaScript(
            """
            document.querySelector('[data-list-item-id="chat-messages___1_104"]')
              .setAttribute('data-list-item-id', 'chat-messages___1_105')
            """
        )
        try await waitForRuntime()
        XCTAssertEqual(recorder.notificationPayloads.count, 4)

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
        XCTAssertEqual(recorder.notificationPayloads.count, 4)

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
        XCTAssertEqual(recorder.notificationPayloads.count, 5)

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
        XCTAssertEqual(recorder.notificationPayloads.count, 5)
    }

    func testMentionFallbackSurvivesExactNotificationHookChanges() async throws {
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
            window['\(DiscordCSSComposer.notificationBridgeKey)']
              .capturesNotificationSounds = true
            """
        )

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
        XCTAssertEqual(recorder.notificationPayloads.count, 1)

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
        XCTAssertEqual(recorder.notificationPayloads.count, 1)

        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.notificationBridgeUserScriptSource(isEnabled: true)
        )
        let exactSoundCaptureWasReplaced = try await webView.evaluateJavaScript(
            """
            (() => {
              const bridge =
                window['\(DiscordCSSComposer.notificationBridgeKey)'];
              bridge.capturesNotificationSounds = true;
              HTMLMediaElement.prototype.play = bridge.originalMediaPlay;
              return bridge.capturesNotificationSounds &&
                HTMLMediaElement.prototype.play !== bridge.mediaPlayProxy;
            })()
            """
        ) as! Bool
        XCTAssertTrue(exactSoundCaptureWasReplaced)

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
        XCTAssertEqual(recorder.notificationPayloads.count, 2)
        XCTAssertTrue(recorder.notificationPayloads.allSatisfy { Set($0.keys) == ["type"] })
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
        let railDidPublishRerender = try await waitForRailItemIDs(
            ["server:2"],
            recorder: recorder
        )
        XCTAssertTrue(
            railDidPublishRerender,
            "The debounced rail bridge did not publish the rerendered server in time."
        )
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
            "window['\(DiscordCSSComposer.runtimeKey)']?.version === 7"
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

    func testSettingsBridgeMountsInsideDiscordSettingsAndPostsTypedChanges() async throws {
        let recorder = RuntimeMessageRecorder()
        let (webView, navigationWaiter) = try await loadFixture(messageRecorder: recorder)
        _ = navigationWaiter
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const shell = document.createElement('div');
              shell.className = 'standardSidebarView_fixture';
              shell.innerHTML = `
                <aside class="sidebarRegion_fixture"><nav class="sidebar_fixture">
                  <button id="discord-settings-item" role="tab">Discord setting</button>
                </nav></aside>
                <main class="contentRegion_fixture"><div class="contentColumn_fixture">Discord content</div></main>`;
              document.body.appendChild(shell);
            })()
            """
        )
        let snapshot = SideCordSettingsSnapshot(
            sidebarEdge: "right",
            edgeHoverEnabled: true,
            sidebarWidth: 420,
            sidebarInset: 16,
            discordLayoutMode: "focus",
            floatingRailEnabled: true,
            visualTheme: "systemGlass",
            themeAccent: "white",
            themeIntensity: 0.75,
            themeColorScheme: "dark",
            notificationGlowEnabled: true,
            attentionGlowColor: "white",
            attentionGlowStrength: "strong",
            incomingCallCardEnabled: true,
            pluginsInstalled: 3,
            pluginsEnabled: 2
        )
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.settingsBridgeUserScriptSource(snapshot: snapshot)
        )
        try await waitForRuntime()

        let opened = try await webView.evaluateJavaScript(
            DiscordCSSComposer.openSideCordSettingsSource()
        ) as? Bool
        XCTAssertEqual(opened, true)
        let mounted = try await webView.evaluateJavaScript(
            """
            (() => ({
              nav: !!document.querySelector('[data-sidecord-settings-nav]'),
              page: !!document.querySelector('[data-sidecord-settings-page]'),
              visible: !document.querySelector('[data-sidecord-settings-page]').hidden,
              accent: document.querySelector('[data-sidecord-key="themeAccent"]').value,
              pluginText: document.querySelector('[data-sidecord-settings-page]').textContent.includes('2 of 3 plugins enabled')
            }))()
            """
        ) as! [String: Any]
        XCTAssertEqual(mounted["nav"] as? Bool, true)
        XCTAssertEqual(mounted["page"] as? Bool, true)
        XCTAssertEqual(mounted["visible"] as? Bool, true)
        XCTAssertEqual(mounted["accent"] as? String, "white")
        XCTAssertEqual(mounted["pluginText"] as? Bool, true)

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const input = document.querySelector('[data-sidecord-key="themeIntensity"]');
              input.value = '0.4';
              input.dispatchEvent(new Event('change', { bubbles: true }));
            })()
            """
        )
        try await waitForRuntime()
        let mutation = recorder.messages.last(where: { $0["type"] as? String == "settingsSet" })
        XCTAssertEqual(mutation?["key"] as? String, "themeIntensity")
        let mutationValue = try XCTUnwrap(mutation?["value"] as? Double)
        XCTAssertEqual(mutationValue, 0.4, accuracy: 0.001)
        XCTAssertNotNil(recorder.messages.last(where: {
            $0["type"] as? String == "settingsHealth"
                && $0["categoryInjected"] as? Bool == true
        }))
    }

    func testNitroQuestionMarkArtworkUsesStableFallback() async throws {
        let (webView, navigationWaiter) = try await loadFixture()
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
              const link = document.createElement('a');
              link.id = 'nitro-fixture';
              link.innerHTML = `
                <span id="broken-image-wrapper"><img id="broken-nitro-image" alt="?" src="data:image/png;base64,iVBORw0KGgo="></span>
                <span id="broken-text-wrapper"><i id="broken-nitro-text">?</i></span>
                <span>Nitro</span>`;
              document.body.appendChild(link);

              const renderedLink = document.createElement('a');
              renderedLink.id = 'rendered-nitro-fixture';
              renderedLink.innerHTML = `
                <div id="rendered-nitro-layout" class="layout_fixture">
                  <div id="rendered-nitro-artwork" class="avatar_fixture"><canvas></canvas></div>
                  <span>Nitro</span>
                </div>`;
              document.body.appendChild(renderedLink);
            })()
            """
        )
        try await Task.sleep(for: .milliseconds(300))

        let state = try await webView.evaluateJavaScript(
            """
            (() => ({
              imageMarked: document.getElementById('broken-nitro-image')
                .hasAttribute('data-sidecord-nitro-broken-artwork'),
              imageFallback: document.getElementById('broken-image-wrapper')
                .hasAttribute('data-sidecord-nitro-icon-fallback'),
              textMarked: document.getElementById('broken-nitro-text')
                .hasAttribute('data-sidecord-nitro-broken-artwork'),
              textFallback: document.getElementById('broken-text-wrapper')
                .hasAttribute('data-sidecord-nitro-icon-fallback'),
              imageDisplay: getComputedStyle(document.getElementById('broken-nitro-image')).display,
              textDisplay: getComputedStyle(document.getElementById('broken-nitro-text')).display,
              renderedArtworkMarked: document.getElementById('rendered-nitro-artwork')
                .hasAttribute('data-sidecord-nitro-static-artwork'),
              renderedWrapperMarked: document.getElementById('rendered-nitro-layout')
                .hasAttribute('data-sidecord-nitro-static-wrapper'),
              renderedArtworkDisplay: getComputedStyle(
                document.getElementById('rendered-nitro-artwork')
              ).display,
              renderedFallbackContent: getComputedStyle(
                document.getElementById('rendered-nitro-layout'), '::before'
              ).content
            }))()
            """
        ) as! [String: Any]
        XCTAssertEqual(state["imageMarked"] as? Bool, true)
        XCTAssertEqual(state["imageFallback"] as? Bool, true)
        XCTAssertEqual(state["textMarked"] as? Bool, true)
        XCTAssertEqual(state["textFallback"] as? Bool, true)
        XCTAssertEqual(state["imageDisplay"] as? String, "none")
        XCTAssertEqual(state["textDisplay"] as? String, "none")
        XCTAssertEqual(state["renderedArtworkMarked"] as? Bool, true)
        XCTAssertEqual(state["renderedWrapperMarked"] as? Bool, true)
        XCTAssertEqual(state["renderedArtworkDisplay"] as? String, "none")
        XCTAssertEqual(state["renderedFallbackContent"] as? String, "\"✦\"")
    }

    func testSettingsBridgeWaitsForDiscordsLazyStructuralSettingsLayer() async throws {
        let recorder = RuntimeMessageRecorder()
        let (webView, navigationWaiter) = try await loadFixture(messageRecorder: recorder)
        _ = navigationWaiter
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const trigger = document.createElement('button');
              trigger.setAttribute('aria-label', 'Paramètres utilisateur');
              trigger.addEventListener('click', () => setTimeout(() => {
                const shell = document.createElement('div');
                shell.className = 'standardSidebarView__23e6b';
                shell.innerHTML = `
                  <aside class="sidebarRegion__23e6b"><div class="sidebarRegionScroller__23e6b">
                    <nav class="sidebar__23e6b"><div class="side_b3f026">
                      <div class="header_b3f026">Activité</div>
                      <div class="item_b3f026 selected_b3f026">Confidentialité des activités</div>
                      <div class="item_b3f026">Notifications</div>
                      <div class="separator_b3f026"></div>
                      <div class="item_b3f026 colorDanger_b3f026">Déconnexion</div>
                    </div></nav>
                  </div></aside>
                  <main class="contentRegion__23e6b"><div class="contentRegionScroller__23e6b">
                    <div class="contentColumn__23e6b">Account</div>
                  </div></main>`;
                document.body.appendChild(shell);
              }, 180));
              document.body.appendChild(trigger);
              const router = { openUserSettings() { window.__sidecordRouterWasCalled = true; } };
              const require = {
                b: 'https://discord.com/assets/',
                c: { router: { exports: { router } } },
                m: {}
              };
              const chunks = [];
              chunks.push = chunk => {
                if (typeof chunk?.[2] === 'function') chunk[2](require);
                return chunks.length;
              };
              window.webpackChunkdiscord_app = chunks;
            })()
            """
        )
        let snapshot = SideCordSettingsSnapshot(
            sidebarEdge: "right",
            edgeHoverEnabled: true,
            sidebarWidth: 420,
            sidebarInset: 16,
            discordLayoutMode: "full",
            floatingRailEnabled: true,
            visualTheme: "discord",
            themeAccent: "blurple",
            themeIntensity: 1,
            themeColorScheme: "system",
            notificationGlowEnabled: true,
            attentionGlowColor: "followTheme",
            attentionGlowStrength: "normal",
            incomingCallCardEnabled: true,
            pluginsInstalled: 0,
            pluginsEnabled: 0
        )
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.settingsBridgeUserScriptSource(snapshot: snapshot)
        )
        let started = try await webView.evaluateJavaScript(
            DiscordCSSComposer.openSideCordSettingsSource()
        ) as? Bool
        XCTAssertEqual(started, true)
        try await Task.sleep(for: .milliseconds(650))

        let state = try await webView.evaluateJavaScript(
            """
            (() => {
              const nav = document.querySelector('[data-sidecord-settings-nav]');
              const page = document.querySelector('[data-sidecord-settings-page]');
              return {
                mounted: !!nav && !!page,
                selected: nav?.getAttribute('aria-selected'),
                nativeClass: nav?.classList.contains('item_b3f026'),
                visible: page ? !page.hidden : false,
                heading: nav?.previousElementSibling?.textContent,
                beforeLogout: !!nav?.nextElementSibling?.classList.contains('colorDanger_b3f026'),
                routerWasCalled: window.__sidecordRouterWasCalled === true
              };
            })()
            """
        ) as! [String: Any]
        XCTAssertEqual(state["mounted"] as? Bool, true)
        XCTAssertEqual(state["selected"] as? String, "true")
        XCTAssertEqual(state["nativeClass"] as? Bool, true)
        XCTAssertEqual(state["visible"] as? Bool, true)
        XCTAssertEqual(state["heading"] as? String, "SideCord")
        XCTAssertEqual(state["beforeLogout"] as? Bool, true)
        XCTAssertEqual(state["routerWasCalled"] as? Bool, true)
    }

    func testSettingsBridgeMountsInDiscordsCompactSettingsSections() async throws {
        let recorder = RuntimeMessageRecorder()
        let (webView, navigationWaiter) = try await loadFixture(messageRecorder: recorder)
        _ = navigationWaiter
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const shell = document.createElement('div');
              shell.className = 'container_abd9a8';
              shell.innerHTML = `
                <aside class="sidebar__409aa"><nav class="nav__409aa">
                  <div class="navScroller__409aa"><ul class="sublist__409aa" role="list">
                    <li class="section__409aa">
                      <div class="sectionLabel__409aa"><h3 class="label__409aa">Experience</h3></div>
                      <ul class="sectionList__409aa"><li class="itemContainer_caf372">
                        <div class="item_caf372 active_caf372" role="link"><span>Appearance</span></div>
                      </li></ul>
                    </li>
                    <li class="section__409aa">
                      <div class="sectionLabel__409aa"><h3 class="label__409aa">Activity</h3></div>
                      <ul class="sectionList__409aa"><li class="itemContainer_caf372">
                        <div class="item_caf372" role="link"><span>Activity Privacy</span></div>
                      </li></ul>
                    </li>
                    <li class="section__409aa"><span>Utility</span><ul class="sectionList__409aa">
                      <li class="itemContainer_caf372"><div class="item_caf372 destructive_caf372" role="link"><span>Log Out</span></div></li>
                    </ul></li>
                  </ul></div>
                </nav></aside>
                <div class="content_e9e3ed"><div class="contentBody_e9e3ed">Discord content</div></div>`;
              document.body.appendChild(shell);
            })()
            """
        )
        let snapshot = SideCordSettingsSnapshot(
            sidebarEdge: "right",
            edgeHoverEnabled: true,
            sidebarWidth: 420,
            sidebarInset: 16,
            discordLayoutMode: "full",
            floatingRailEnabled: true,
            visualTheme: "discord",
            themeAccent: "white",
            themeIntensity: 1,
            themeColorScheme: "dark",
            notificationGlowEnabled: true,
            attentionGlowColor: "white",
            attentionGlowStrength: "normal",
            incomingCallCardEnabled: true,
            pluginsInstalled: 1,
            pluginsEnabled: 1,
            plugins: [
                SideCordPluginSettingsSnapshot(
                    identifier: "dev.sidecord.fixture",
                    name: "Fixture Plugin",
                    version: "1.0.0",
                    enabled: true
                )
            ],
            marketplaceConfigured: true,
            marketplacePlugins: [
                SideCordMarketplaceSettingsSnapshot(
                    identifier: "com.mathieudvv.youtube-music",
                    name: "YouTube Music",
                    version: "1.2.4",
                    summary: "Compact YouTube Music player for SideCord",
                    repository: "https://github.com/MathieuDvv/sidecord-plugin-youtube-music",
                    publisher: "MathieuDvv",
                    verifiedPublisher: true,
                    categories: ["music", "web-panel"],
                    permissions: ["webPanel", "backgroundAudio"],
                    networkHosts: ["music.youtube.com"],
                    installedVersion: nil,
                    updateAvailable: false,
                    blockedReason: nil
                )
            ]
        )
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.settingsBridgeUserScriptSource(snapshot: snapshot)
        )
        try await waitForRuntime()
        let opened = try await webView.evaluateJavaScript(
            DiscordCSSComposer.openSideCordSettingsSource()
        ) as? Bool
        XCTAssertEqual(opened, true)

        let state = try await webView.evaluateJavaScript(
            """
            (() => {
              const section = document.querySelector('[data-sidecord-settings-section]');
              const navs = [...document.querySelectorAll('[data-sidecord-settings-nav]')];
              const nav = document.querySelector('[data-sidecord-settings-nav="settings"]');
              const page = document.querySelector('[data-sidecord-settings-page]');
              const sections = [...document.querySelector('.sublist__409aa').children];
              return {
                sectionText: section?.textContent?.replace(/\\s+/g, ' ').trim(),
                navLabels: navs.map(item => item.getAttribute('aria-label')),
                distinctIcons: new Set(navs.map(item => item.querySelector('path')?.getAttribute('d'))).size,
                nativeSectionClass: section?.classList.contains('section__409aa'),
                nativeItemClass: nav?.classList.contains('item_caf372'),
                beforeUtility: sections.indexOf(section) === sections.length - 2,
                selected: nav?.classList.contains('active_caf372'),
                pageVisible: page ? !page.hidden : false,
                pageInContent: !!page?.closest('.content_e9e3ed'),
                discordPanelHidden: getComputedStyle(document.querySelector('.contentBody_e9e3ed')).display === 'none',
                visibleSettingsSections: [...page.querySelectorAll('.sc-section')]
                  .filter(item => getComputedStyle(item).display !== 'none')
                  .map(item => item.getAttribute('data-sidecord-page'))
              };
            })()
            """
        ) as! [String: Any]
        XCTAssertEqual(state["sectionText"] as? String, "SideCordThemeLayoutSettingsPlugins")
        XCTAssertEqual(state["navLabels"] as? [String], ["Theme", "Layout", "Settings", "Plugins"])
        XCTAssertEqual(state["distinctIcons"] as? Int, 4)
        XCTAssertEqual(state["nativeSectionClass"] as? Bool, true)
        XCTAssertEqual(state["nativeItemClass"] as? Bool, true)
        XCTAssertEqual(state["beforeUtility"] as? Bool, true)
        XCTAssertEqual(state["selected"] as? Bool, true)
        XCTAssertEqual(state["pageVisible"] as? Bool, true)
        XCTAssertEqual(state["pageInContent"] as? Bool, true)
        XCTAssertEqual(state["discordPanelHidden"] as? Bool, true)
        XCTAssertEqual(state["visibleSettingsSections"] as? [String], ["settings", "settings"])

        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const range = document.querySelector('[data-sidecord-key="sidebarWidth"]');
              range.dispatchEvent(new Event('pointerdown', { bubbles:true }));
              range.value = '780';
              range.dispatchEvent(new Event('input', { bubbles:true }));
            })()
            """
        )
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.settingsBridgeUserScriptSource(snapshot: snapshot)
        )
        let activeSliderValue = try await webView.evaluateJavaScript(
            "document.querySelector('[data-sidecord-key=\"sidebarWidth\"]').value"
        ) as? String
        XCTAssertEqual(activeSliderValue, "780")
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const range = document.querySelector('[data-sidecord-key="sidebarWidth"]');
              range.dispatchEvent(new Event('pointerup', { bubbles:true }));
            })()
            """
        )

        _ = try await webView.evaluateJavaScript(
            "document.querySelector('[data-sidecord-settings-nav=\"theme\"]').click()"
        )
        let themeState = try await webView.evaluateJavaScript(
            """
            (() => {
              const page = document.querySelector('[data-sidecord-settings-page]');
              return {
                title: page.querySelector('[data-sidecord-page-title]').textContent,
                visiblePages: [...page.querySelectorAll('.sc-section')]
                  .filter(item => getComputedStyle(item).display !== 'none')
                  .map(item => item.getAttribute('data-sidecord-page')),
                selected: document.querySelector('[data-sidecord-settings-nav="theme"]')
                  .classList.contains('active_caf372')
              };
            })()
            """
        ) as! [String: Any]
        XCTAssertEqual(themeState["title"] as? String, "SideCord Theme")
        XCTAssertEqual(themeState["visiblePages"] as? [String], ["theme"])
        XCTAssertEqual(themeState["selected"] as? Bool, true)

        _ = try await webView.evaluateJavaScript(
            "document.querySelector('[data-sidecord-action=\"resetTheme\"]').click()"
        )
        _ = try await webView.evaluateJavaScript(
            "document.querySelector('[data-sidecord-settings-nav=\"plugins\"]').click()"
        )
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const toggle = document.querySelector('[data-sidecord-plugin-enabled]');
              window.__sidecordPluginToggleBeforeSnapshot = toggle;
              toggle.dispatchEvent(new Event('pointerdown', { bubbles:true }));
            })()
            """
        )
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.settingsBridgeUserScriptSource(snapshot: snapshot)
        )
        let pluginState = try await webView.evaluateJavaScript(
            """
            (() => {
              const toggle = document.querySelector('[data-sidecord-plugin-enabled]');
              const survivedSnapshot = toggle === window.__sidecordPluginToggleBeforeSnapshot;
              toggle.dispatchEvent(new Event('pointerup', { bubbles:true }));
              toggle.click();
              const search = document.querySelector('[data-sidecord-plugin-search]');
              search.value = 'youtube';
              search.dispatchEvent(new Event('input', { bubbles:true }));
              document.querySelector('[data-sidecord-marketplace-list] .sc-button').click();
              document.querySelector('[data-sidecord-action="refreshMarketplace"]').click();
              document.querySelector('[data-sidecord-action="installPlugin"]').click();
              document.querySelector('[data-sidecord-plugin-remove]').click();
              return {
                text: document.querySelector('[data-sidecord-plugin-list]').textContent,
                marketplaceText: document.querySelector('[data-sidecord-marketplace-list]').textContent,
                searchValue: search.value,
                installButton: !!document.querySelector('[data-sidecord-action="installPlugin"]'),
                removeButton: !!document.querySelector('[data-sidecord-plugin-remove]'),
                survivedSnapshot
              };
            })()
            """
        ) as! [String: Any]
        XCTAssertTrue((pluginState["text"] as? String)?.contains("Fixture Plugin") == true)
        XCTAssertTrue((pluginState["marketplaceText"] as? String)?.contains("YouTube Music") == true)
        XCTAssertTrue((pluginState["marketplaceText"] as? String)?.contains("Published by @MathieuDvv") == true)
        XCTAssertEqual(pluginState["searchValue"] as? String, "youtube")
        XCTAssertEqual(pluginState["installButton"] as? Bool, true)
        XCTAssertEqual(pluginState["removeButton"] as? Bool, true)
        XCTAssertEqual(pluginState["survivedSnapshot"] as? Bool, true)
        XCTAssertTrue(recorder.messages.contains { message in
            message["type"] as? String == "settingsAction"
                && message["action"] as? String == "installMarketplacePlugin"
                && message["identifier"] as? String == "com.mathieudvv.youtube-music"
        })
        XCTAssertTrue(recorder.messages.contains { message in
            message["type"] as? String == "settingsAction"
                && message["action"] as? String == "refreshMarketplace"
        })
        XCTAssertTrue(recorder.messages.contains { message in
            message["type"] as? String == "settingsAction"
                && message["action"] as? String == "resetTheme"
        })
        XCTAssertTrue(recorder.messages.contains { message in
            message["type"] as? String == "settingsAction"
                && message["action"] as? String == "setPluginEnabled"
                && message["identifier"] as? String == "dev.sidecord.fixture"
                && message["value"] as? Bool == false
        })
        XCTAssertTrue(recorder.messages.contains { message in
            message["type"] as? String == "settingsAction"
                && message["action"] as? String == "installPlugin"
        })
        XCTAssertTrue(recorder.messages.contains { message in
            message["type"] as? String == "settingsAction"
                && message["action"] as? String == "removePlugin"
                && message["identifier"] as? String == "dev.sidecord.fixture"
        })

        _ = try await webView.evaluateJavaScript(
            "document.querySelector('.section__409aa [role=\"link\"]:not([data-sidecord-settings-nav])').click()"
        )
        let restored = try await webView.evaluateJavaScript(
            """
            (() => ({
              pageHidden: document.querySelector('[data-sidecord-settings-page]').hidden,
              discordPanelDisplay: getComputedStyle(document.querySelector('.contentBody_e9e3ed')).display,
              discordPanelAriaHidden: document.querySelector('.contentBody_e9e3ed').getAttribute('aria-hidden')
            }))()
            """
        ) as! [String: Any]
        XCTAssertEqual(restored["pageHidden"] as? Bool, true)
        XCTAssertNotEqual(restored["discordPanelDisplay"] as? String, "none")
        XCTAssertTrue(restored["discordPanelAriaHidden"] is NSNull)
    }

    func testSettingsBridgePatchesDiscordsNativeSettingsLayoutModel() async throws {
        let (webView, navigationWaiter) = try await loadFixture()
        _ = navigationWaiter
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const root = {
                key: '$Root',
                buildLayout: () => [
                  { key: 'user_section', type: 1 },
                  { key: 'activity_section', type: 1 },
                  { key: 'utility_section', type: 1 }
                ]
              };
              const router = {
                openUserSettings(key, options) {
                  window.__sidecordOpenedNativeSettings = { key, section: options?.section };
                }
              };
              const react = {
                createElement() {}, useState() {}, useEffect() {}
              };
              const require = {
                b: 'https://discord.com/assets/',
                c: {
                  react: { exports: react }
                },
                m: {}
              };
              const chunks = [];
              chunks.push = chunk => {
                if (typeof chunk?.[2] === 'function') chunk[2](require);
                return chunks.length;
              };
              window.webpackChunkdiscord_app = chunks;
              window.__sidecordRootLayout = root;
              window.__sidecordSettingsModules = { require, root, router };
            })()
            """
        )
        let snapshot = SideCordSettingsSnapshot(
            sidebarEdge: "right",
            edgeHoverEnabled: true,
            sidebarWidth: 420,
            sidebarInset: 16,
            discordLayoutMode: "full",
            floatingRailEnabled: true,
            visualTheme: "discord",
            themeAccent: "white",
            themeIntensity: 1,
            themeColorScheme: "dark",
            notificationGlowEnabled: true,
            attentionGlowColor: "white",
            attentionGlowStrength: "normal",
            incomingCallCardEnabled: true,
            pluginsInstalled: 0,
            pluginsEnabled: 0
        )
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.settingsBridgeUserScriptSource(snapshot: snapshot)
        )
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const modules = window.__sidecordSettingsModules;
              modules.require.c.root = { exports: { root: modules.root } };
              modules.require.c.router = { exports: { router: modules.router } };
              document.body.appendChild(document.createElement('div'));
            })()
            """
        )
        try await waitForRuntime()
        let opened = try await webView.evaluateJavaScript(
            DiscordCSSComposer.openSideCordSettingsSource()
        ) as? Bool
        XCTAssertEqual(opened, true)

        let state = try await webView.evaluateJavaScript(
            """
            (() => {
              const layout = window.__sidecordRootLayout.buildLayout();
              const section = layout.find(entry => entry?.key === 'sidecord_section');
              const items = section?.buildLayout?.() || [];
              const item = items.find(entry => entry?.key === 'sidecord_settings');
              const panel = item?.buildLayout?.()[0];
              const category = panel?.buildLayout?.()[0];
              const custom = category?.buildLayout?.()[0];
              return {
                afterActivity: layout.findIndex(entry => entry?.key === 'sidecord_section') ===
                  layout.findIndex(entry => entry?.key === 'activity_section') + 1,
                sectionType: section?.type,
                itemKeys: items.map(entry => entry?.key),
                itemType: item?.type,
                panelKey: panel?.key,
                customType: custom?.type,
                openedKey: window.__sidecordOpenedNativeSettings?.key,
                openedSection: window.__sidecordOpenedNativeSettings?.section
              };
            })()
            """
        ) as! [String: Any]
        XCTAssertEqual(state["afterActivity"] as? Bool, true)
        XCTAssertEqual(state["sectionType"] as? Int, 1)
        XCTAssertEqual(
            state["itemKeys"] as? [String],
            ["sidecord_theme", "sidecord_layout", "sidecord_settings", "sidecord_plugins"]
        )
        XCTAssertEqual(state["itemType"] as? Int, 2)
        XCTAssertEqual(state["panelKey"] as? String, "sidecord_settings_panel")
        XCTAssertEqual(state["customType"] as? Int, 19)
        XCTAssertEqual(state["openedKey"] as? String, "sidecord_settings_panel")
        XCTAssertEqual(state["openedSection"] as? String, "sidecord_settings")
    }

    func testSettingsBridgeCogOpensDiscordSettingsBeforeLazyLayoutLoads() async throws {
        let (webView, navigationWaiter) = try await loadFixture()
        _ = navigationWaiter
        _ = try await webView.evaluateJavaScript(
            """
            (() => {
              const router = { openUserSettings(key) { window.__sidecordCogOpenedKey = key; } };
              const require = {
                b: 'https://discord.com/assets/',
                c: { router: { exports: { router } } },
                m: {}
              };
              const chunks = [];
              chunks.push = chunk => {
                if (typeof chunk?.[2] === 'function') chunk[2](require);
                return chunks.length;
              };
              window.webpackChunkdiscord_app = chunks;
            })()
            """
        )
        let snapshot = SideCordSettingsSnapshot(
            sidebarEdge: "right",
            edgeHoverEnabled: true,
            sidebarWidth: 420,
            sidebarInset: 16,
            discordLayoutMode: "full",
            floatingRailEnabled: true,
            visualTheme: "discord",
            themeAccent: "white",
            themeIntensity: 1,
            themeColorScheme: "dark",
            notificationGlowEnabled: true,
            attentionGlowColor: "white",
            attentionGlowStrength: "normal",
            incomingCallCardEnabled: true,
            pluginsInstalled: 0,
            pluginsEnabled: 0
        )
        _ = try await webView.evaluateJavaScript(
            DiscordCSSComposer.settingsBridgeUserScriptSource(snapshot: snapshot)
        )
        let opened = try await webView.evaluateJavaScript(
            DiscordCSSComposer.openSideCordSettingsSource()
        ) as? Bool
        let key = try await webView.evaluateJavaScript("window.__sidecordCogOpenedKey") as? String
        XCTAssertEqual(opened, true)
        XCTAssertEqual(key, "my_account_panel")
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

    private func waitForRailItemIDs(
        _ expectedIDs: [String],
        recorder: RuntimeMessageRecorder
    ) async throws -> Bool {
        for _ in 0..<30 {
            let identifiers = recorder.latestRailItems?.compactMap { $0["id"] as? String }
            if identifiers == expectedIDs { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
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

    private func waitForNotificationSoundCapture(
        in webView: WKWebView
    ) async throws -> Bool {
        for _ in 0..<30 {
            let isReady = try await webView.evaluateJavaScript(
                "window['\(DiscordCSSComposer.notificationBridgeKey)']?.capturesNotificationSounds === true"
            ) as! Bool
            if isReady { return true }
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
