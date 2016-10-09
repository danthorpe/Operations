//
//  ProcedureKit
//
//  Copyright © 2016 ProcedureKit. All rights reserved.
//

import XCTest
import ProcedureKit
import TestingProcedureKit
@testable import ProcedureKitLocation

class CLLocationManagerTests: XCTestCase, CLLocationManagerDelegate {

    func test__extension_set_delegate_works() {
        let manager = CLLocationManager.make()
        manager.pk_set(delegate: self)
        XCTAssertNotNil(manager.delegate)
    }
}

class CLAuthorizationStatusTests: XCTestCase {

    func test__given_status_not_determined__requirements_not_met() {
        let status = CLAuthorizationStatus.notDetermined
        XCTAssertFalse(status.meets(requirement: .whenInUse))
        XCTAssertFalse(status.meets(requirement: nil))
    }

    func test__given_status_restricted__requirements_not_met() {
        let status = CLAuthorizationStatus.restricted
        XCTAssertFalse(status.meets(requirement: .whenInUse))
        XCTAssertFalse(status.meets(requirement: nil))
    }

    func test__given_status_denied__requirements_not_met() {
        let status = CLAuthorizationStatus.denied
        XCTAssertFalse(status.meets(requirement: .whenInUse))
        XCTAssertFalse(status.meets(requirement: nil))
    }

    #if os(iOS)
    func test__given_status_authorized_when_in_use__requirement_always_not_met() {
        let status = CLAuthorizationStatus.authorizedWhenInUse
        XCTAssertFalse(status.meets(requirement: .always))
        XCTAssertFalse(status.meets(requirement: nil))
    }

    func test__given_status_authorized_when_in_use__requirement_when_in_use_met() {
        let status = CLAuthorizationStatus.authorizedWhenInUse
        XCTAssertTrue(status.meets(requirement: .whenInUse))
        XCTAssertFalse(status.meets(requirement: nil))
    }
    #endif

    func test__given_status_authorized_always__requirement_when_in_use_met() {
        let status = CLAuthorizationStatus.authorizedAlways
        XCTAssertTrue(status.meets(requirement: .whenInUse))
        XCTAssertTrue(status.meets(requirement: nil))
    }

    func test__given_status_authorized_always__requirement_always_met() {
        let status = CLAuthorizationStatus.authorizedAlways
        XCTAssertTrue(status.meets(requirement: .always))
        XCTAssertTrue(status.meets(requirement: nil))
    }
}

class LocationCapabilityTests: XCTestCase {

    var registrar: TestableLocationServicesRegistrar!
    var capability: Capability.Location!

    override func setUp() {
        super.setUp()
        registrar = TestableLocationServicesRegistrar()
        capability = Capability.Location()
        capability.registrar = registrar
    }

    override func tearDown() {
        registrar = nil
        capability = nil
        super.tearDown()
    }

    func test__requirement_is_set() {
        XCTAssertEqual(capability.requirement, LocationUsage.whenInUse)
    }

    func test__is_available_queries_registrar() {
        XCTAssertTrue(capability.isAvailable())
        XCTAssertTrue(registrar.didCheckServiceEnabled)
    }

    func test__authorization_status_queries_register() {
        capability.getAuthorizationStatus { XCTAssertEqual($0, CLAuthorizationStatus.notDetermined) }
        XCTAssertTrue(registrar.didCheckAuthorizationStatus)
    }

    func test__given_service_disabled__requesting_authorization_returns_directly() {
        registrar.servicesEnabled = false
        var didComplete = false
        capability.requestAuthorization { 
            didComplete = true
        }
        XCTAssertTrue(registrar.didCheckServiceEnabled)
        XCTAssertFalse(registrar.didRequestAuthorization)
        XCTAssertNil(registrar.didRequestAuthorizationForUsage)
        XCTAssertTrue(didComplete)
    }

    func test__given_not_determined_request_authorization() {
        var didComplete = false
        capability.requestAuthorization {
            didComplete = true
        }
        XCTAssertTrue(registrar.didCheckServiceEnabled)
        XCTAssertTrue(registrar.didRequestAuthorization)
        XCTAssertEqual(registrar.didRequestAuthorizationForUsage, .whenInUse)
        XCTAssertTrue(registrar.didSetDelegate)
        XCTAssertTrue(didComplete)
    }

    #if os(iOS)
    func test__given_when_in_use_require_always_request_authorization() {
        registrar.authorizationStatus = .authorizedWhenInUse
        capability = Capability.Location(.always)
        capability.registrar = registrar
        var didComplete = false
        capability.requestAuthorization {
            didComplete = true
        }
        XCTAssertTrue(registrar.didCheckServiceEnabled)
        XCTAssertTrue(registrar.didRequestAuthorization)
        XCTAssertEqual(registrar.didRequestAuthorizationForUsage, .always)
        XCTAssertTrue(registrar.didSetDelegate)
        XCTAssertTrue(didComplete)
    }
    #endif

    func test__given_denied_does_not_request_authorization() {
        registrar.authorizationStatus = .denied
        var didComplete = false
        capability.requestAuthorization {
            didComplete = true
        }
        XCTAssertFalse(registrar.didRequestAuthorization)
        XCTAssertNil(registrar.didRequestAuthorizationForUsage)
        XCTAssertTrue(didComplete)
    }


    func test__given_already_authorized_sufficiently_does_not_request_authorization() {
        registrar.authorizationStatus = .authorizedAlways
        capability = Capability.Location(.whenInUse)
        capability.registrar = registrar
        var didComplete = false
        capability.requestAuthorization {
            didComplete = true
        }
        XCTAssertFalse(registrar.didRequestAuthorization)
        XCTAssertNil(registrar.didRequestAuthorizationForUsage)
        XCTAssertTrue(didComplete)
    }

}
