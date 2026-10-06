/// The single isolation domain of cordis. It replaces JavaScript's single thread:
/// contexts, fibers, services, listeners and disposers all run on this actor.
@globalActor public actor CordisActor {
  public static let shared = CordisActor()
}
