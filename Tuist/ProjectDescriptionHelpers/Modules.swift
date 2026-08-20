// AUTO-GENERATED. DO NOT EDIT.
// Source of truth: directory structure under Projects/<Layer>/<Module>/Sources
import Foundation
import ProjectDescription
import TargetPlugin

public enum Module: String, ModuleAppType {
  case App
  public var name: String { rawValue }
}

public extension Module {
  enum Feature: String, CaseIterable, ModuleFeatureType {
    case Repository
    public var name: String { rawValue }
  }
}

public extension Module {
  enum Domain: String, CaseIterable, ModuleDomainType {
    case Git
    public var name: String { rawValue }
  }
}

public extension Module {
  enum Data: String, CaseIterable, ModuleDataType {
    case Git
    public var name: String { rawValue }
  }
}

extension ModuleAppType where Self == Module {
  public static var app: Module { Module.App }
}

extension ModuleFeatureType where Self == Module.Feature {
  public static var repository: Module.Feature { Module.Feature.Repository }
}

extension ModuleDomainType where Self == Module.Domain {
  public static var git: Module.Domain { Module.Domain.Git }
}

extension ModuleDataType where Self == Module.Data {
  public static var git: Module.Data { Module.Data.Git }
}
