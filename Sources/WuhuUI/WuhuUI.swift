// WuhuUI — Custom Document Layout Engine
//
// Architecture:
//   Element (value descriptors) → Reconciler (diff) → Node (persistent tree)
//   → LayoutEngine (measure + frame assignment) → Renderer (CALayer projection)
//
// The layout tree is purely geometric and completely decoupled from platform views.
// Virtualization, hit-testing, and preference collection all operate on the frame table.

// Re-export everything.
