#if !os(watchOS)
  import Foundation
  import Get
  import SnapshotTesting
  import XCTest

  @testable import PostgREST

  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif

  @MainActor
  final class BuildURLRequestTests: XCTestCase {
    let url = URL(string: "https://example.supabase.co")!

    struct TestCase {
      let name: String
      var record = false
      let build: (PostgrestClient) -> PostgrestBuilder
    }

    func testBuildRequest() async throws {
      @MainActor
      class Delegate: APIClientDelegate {
        var testCase: TestCase!

        func client(_: APIClient, willSendRequest request: inout URLRequest) async throws {
          assertSnapshot(
            matching: request,
            as: .curl,
            named: testCase.name,
            record: testCase.record,
            testName: "testBuildRequest()"
          )

          struct SomeError: Error {}
          throw SomeError()
        }
      }
      let delegate = Delegate()
      let client = PostgrestClient(url: url, schema: nil, apiClientDelegate: delegate)

      let testCases: [TestCase] = [
        TestCase(name: "select all users where email ends with '@supabase.co'") { client in
          client.from("users")
            .select()
            .like(column: "email", value: "%@supabase.co")
        },
        TestCase(name: "insert new user") { client in
          client.from("users")
            .insert(values: ["email": "johndoe@supabase.io"])
        },
        TestCase(name: "call rpc") { client in
          client.rpc(fn: "test_fcn", params: ["KEY": "VALUE"])
        },
        TestCase(name: "call rpc without parameter") { client in
          client.rpc(fn: "test_fcn")
        },
        TestCase(name: "test all filters and count") { client in
          var query = client.from("todos").select()

          for op in PostgrestFilterBuilder.Operator.allCases {
            query = query.filter(column: "column", operator: op, value: "Some value")
          }

          return query
        },
        TestCase(name: "test in filter") { client in
          client.from("todos").select().in(column: "id", value: [1, 2, 3])
        },
      ]

      for testCase in testCases {
        delegate.testCase = testCase
        let builder = testCase.build(client)
        builder.adaptRequest(head: false, count: nil)
        _ = try? await builder.execute()
      }
    }

    func testSessionConfiguration() {
      let client = PostgrestClient(url: url, schema: nil)
      let clientInfoHeader = client.api.configuration.sessionConfiguration
        .httpAdditionalHeaders?["X-Client-Info"]
      XCTAssertNotNil(clientInfoHeader)
    }
  }
#endif
