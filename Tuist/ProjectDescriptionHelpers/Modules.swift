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
    case RepositoryChanges
    case RepositoryDiff
    case RepositoryHistory
    case RepositoryOperations
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

public extension Module {
  enum Core: String, CaseIterable, ModuleCoreType {
    case GitCredential
    case RepositoryUI
    public var name: String { rawValue }
  }
}

extension ModuleAppType where Self == Module {
  public static var app: Module { Module.App }
}

extension ModuleFeatureType where Self == Module.Feature {
  public static var repository: Module.Feature { Module.Feature.Repository }
  public static var repositoryChanges: Module.Feature { Module.Feature.RepositoryChanges }
  public static var repositoryDiff: Module.Feature { Module.Feature.RepositoryDiff }
  public static var repositoryHistory: Module.Feature { Module.Feature.RepositoryHistory }
  public static var repositoryOperations: Module.Feature { Module.Feature.RepositoryOperations }
}

extension ModuleDomainType where Self == Module.Domain {
  public static var git: Module.Domain { Module.Domain.Git }
}

extension ModuleDataType where Self == Module.Data {
  public static var git: Module.Data { Module.Data.Git }
}

extension ModuleCoreType where Self == Module.Core {
  public static var gitCredential: Module.Core { Module.Core.GitCredential }
  public static var repositoryUI: Module.Core { Module.Core.RepositoryUI }
}
