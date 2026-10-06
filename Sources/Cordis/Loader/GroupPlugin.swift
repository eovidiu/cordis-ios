/// The built-in plugin behind group entries: while active it runs the
/// group's child entries under its own context, reconciled by id with the
/// loader's rules. Unloading the group disposes its children.
enum GroupPlugin {
  static let name = "group"

  @CordisActor
  static func make(node: EntryNode, loader: Loader) -> FunctionPlugin<NoConfig> {
    FunctionPlugin(name: name) { [weak node, weak loader] ctx, _, scope in
      guard let node, let loader else { return }
      let reconciler = EntryReconciler(ctx: ctx, loader: loader)
      node.children = reconciler
      try scope.collect {
        if node.children === reconciler { node.children = nil }
        await reconciler.disposeAll()
      }
      await reconciler.reconcile(node.entry.children ?? [])
    }
  }
}
