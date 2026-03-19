//
// Copyright (c) 2024-2025 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

@_spi(SwiftOCAPrivate)
import SwiftOCA
import SwiftUI

private struct OcaPropertyErrorView: View {
  let error: Error

  @State
  private var showPopover = false

  var body: some View {
    Button {
      showPopover.toggle()
    } label: {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.yellow)
    }
    .buttonStyle(.plain)
    .popover(isPresented: $showPopover) {
      Text(error.localizedDescription)
        .font(.caption)
        .padding(8)
    }
  }
}

public struct OcaPropertyView<Value: Sendable, Resolved: View>: View {
  let object: OcaRoot
  nonisolated(unsafe) let property: any OcaPropertyRepresentable
  let content: (Value) -> Resolved

  @State
  private var currentValue: Result<Value, Error>?

  public init(
    _ object: OcaRoot,
    _ property: any OcaPropertyRepresentable,
    @ViewBuilder content: @escaping (Value) -> Resolved
  ) {
    self.object = object
    self.property = property
    self.content = content
  }

  public var body: some View {
    Group {
      if let currentValue {
        switch currentValue {
        case let .success(value):
          content(value)
        case let .failure(error):
          OcaPropertyErrorView(error: error)
        }
      } else {
        ProgressView()
      }
    }
    .task {
      await property.subscribe(object)
      do {
        for try await result in property.async {
          switch result {
          case let .success(value):
            if let typed = value as? Value {
              currentValue = .success(typed)
            } else {
              currentValue = .failure(Ocp1Error.status(.badFormat))
            }
          case let .failure(error):
            currentValue = .failure(error)
          }
        }
      } catch {}
    }
  }
}

public struct OcaWritablePropertyView<Value: Sendable, Resolved: View>: View {
  let object: OcaRoot
  nonisolated(unsafe) let property: any OcaPropertySubjectRepresentable
  let content: (Binding<Value>) -> Resolved

  @State
  private var currentValue: Result<Value, Error>?

  public init(
    _ object: OcaRoot,
    _ property: any OcaPropertyRepresentable,
    @ViewBuilder content: @escaping (Binding<Value>) -> Resolved
  ) {
    self.object = object
    self.property = property as! (any OcaPropertySubjectRepresentable)
    self.content = content
  }

  private var binding: Binding<Value> {
    Binding<Value>(
      get: {
        if case let .success(value) = currentValue {
          return value
        }
        preconditionFailure()
      },
      set: { newValue in
        currentValue = .success(newValue)
        Task {
          try? await property._setValue(object, newValue)
        }
      }
    )
  }

  public var body: some View {
    Group {
      if let currentValue {
        switch currentValue {
        case .success:
          content(binding)
        case let .failure(error):
          OcaPropertyErrorView(error: error)
        }
      } else {
        ProgressView()
      }
    }
    .task {
      await property.subscribe(object)
      do {
        for try await result in property.async {
          switch result {
          case let .success(value):
            if let typed = value as? Value {
              currentValue = .success(typed)
            } else {
              currentValue = .failure(Ocp1Error.status(.badFormat))
            }
          case let .failure(error):
            currentValue = .failure(error)
          }
        }
      } catch {}
    }
  }
}
