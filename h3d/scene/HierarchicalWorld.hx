package h3d.scene;

typedef WorldData = {
	var x : Int;
	var y : Int;
	var subdivPow : Float;
	var size : Int;
	var depth : Int;
	var maxDepth : Int;
	var onCreate : HierarchicalWorld -> Void;
}

class HierarchicalWorld extends Object {

	static public var FULL = false;
	static public var DEBUG = false;

	static inline final UNLOCK_COLOR = 0xFFFFFF;
	static inline final LOCK_COLOR = 0xFF0000;

	public var data : WorldData;
	var bounds : h3d.col.Bounds;
	var subdivided(default, set) = false;
	function set_subdivided(v : Bool) {
		subdivided = v;
		updateGraphics();
		return subdivided;
	}
	var debugGraphics : h3d.scene.Graphics;
	// during edition, it's necessary to lock chunks that are being modified.
	var locked(default, set) : Bool = false;
	function set_locked(v : Bool) {
		locked = v;
		updateGraphics();
		return locked;
	}

	function updateGraphics() {
		if ( debugGraphics == null )
			return;
		var hasLockedColor = locked && data.depth == data.maxDepth;
		var color = hasLockedColor ? LOCK_COLOR : UNLOCK_COLOR;
		var s = debugGraphics.material.mainPass.getShader(h3d.shader.FixedColor);
		s.color.setColor(color);
		debugGraphics.lineStyle(hasLockedColor ? 10.0 : 1.0, 0xFFFFFF, 1.0);
	}

	function createGraphics() {
		if ( debugGraphics != null )
			throw "??";
		var b = bounds.clone();
		b.transform(getAbsPos().getInverse());
		b.zMin = 0.0;
		b.zMax = 0.1;
		debugGraphics = new h3d.scene.Box(0xFFFFFF, b, false, this);
		debugGraphics.material.mainPass.setPassName("afterTonemapping");
		debugGraphics.material.shadows = false;
		debugGraphics.material.mainPass.addShader(new h3d.shader.FixedColor(UNLOCK_COLOR));
		updateGraphics();
	}

	public function new(parent, data : WorldData) {
		super(parent);
		this.data = data;
		this.x = data.x;
		this.y = data.y;
		calcAbsPos();
		bounds = new h3d.col.Bounds();
		var halfSize = data.size >> 1;
		// TBD : z bounds? Negative & positive infinity causes bounds to break.
		var pseudoInfinity = 1e10;
		bounds.addPoint(new h3d.col.Point(-halfSize, -halfSize, -pseudoInfinity));
		bounds.addPoint(new h3d.col.Point(halfSize,halfSize, pseudoInfinity));
		bounds.transform(absPos);

		if ( data.depth != 0 && data.onCreate != null ) {
			data.onCreate(this);
		}
	}

	function init() {
		if ( data.depth == 0 && data.onCreate != null )
			data.onCreate(this);
	}

	final function isLeaf() {
		return data.depth == data.maxDepth;
	}

	function canSubdivide() {
		return true;
	}

	function createNode(parent, data) {
		return new HierarchicalWorld(parent, data);
	}

	function subdivide() {
		if ( subdivided || isLeaf() )
			return;
		subdivided = true;
		var childSize = data.size >> 1;
		for ( i in 0...2 ) {
			for ( j in 0...2 ) {
				var halfChildSize = childSize >> 1;
				var childData : WorldData = {
					size : childSize,
					subdivPow : data.subdivPow,
					x : i * childSize - halfChildSize,
					y : j * childSize - halfChildSize,
					depth : data.depth + 1,
					maxDepth : data.maxDepth,
					onCreate : data.onCreate
				};
				var node = createNode(this, childData);
			}
		}
	}

	function removeSubdivisions() {
		if ( !subdivided )
			return;
		subdivided = false;
		var i = children.length;
		while ( i-- > 0 ) {
			if ( Std.isOfType(children[i], HierarchicalWorld) )
				children[i].remove();
		}
	}

	function calcDist(ctx : h3d.scene.RenderContext) {
		return ctx.camera.pos.distance(getAbsPos().getPosition());
	}

	override function syncRec(ctx : h3d.scene.RenderContext) {

		if ( debugGraphics == null && DEBUG ) {
			createGraphics();
		} else if ( debugGraphics != null && !DEBUG ) {
			debugGraphics.remove();
			debugGraphics = null;
		}

		culled = !bounds.inFrustum(ctx.camera.frustum);
		if ( !isLeaf() ) {
			if ( FULL || calcDist(ctx) < data.size * data.subdivPow ) {
				if ( canSubdivide() ) {
					subdivide();
				}
			} else if ( !locked ) {
				removeSubdivisions();
			}
		}
		super.syncRec(ctx);
	}

	override function emitRec(ctx : h3d.scene.RenderContext) {
		if ( culled )
			return;
		super.emitRec(ctx);
	}

	public function getChunkPos(x : Float, y : Float, depth = -1) {
		var root = getRoot();
		var depth = depth;
		if ( depth < 0 )
			depth = data.maxDepth;
		var chunkSize = root.data.size >> depth;
		return new h2d.col.Point((Math.floor(x / chunkSize) + 0.5) * chunkSize,
			(Math.floor(y / chunkSize) + 0.5) * chunkSize);
	}

	public function requestCreateAt(x : Float, y : Float, lock : Bool) {
		if ( !bounds.contains(new h3d.col.Point(x, y, 0.0)) )
			return;
		if ( lock )
			locked = true;
		subdivide();
		for ( c in children ) {
			var node = Std.downcast(c, HierarchicalWorld);
			if ( node == null )
				continue;
			node.requestCreateAt(x, y, lock);
		}
	}

	public function lockAt(x : Float, y : Float) {
		if ( !bounds.contains(new h3d.col.Point(x, y, 0.0)) )
			return;
		locked = true;
		for ( c in children ) {
			var node = Std.downcast(c, HierarchicalWorld);
			if ( node == null )
				continue;
			node.lockAt(x, y);
		}
	}

	public function unlockAt(x : Float, y : Float) {
		if ( !bounds.contains(new h3d.col.Point(x, y, 0.0)) )
			return;
		locked = false;
		for ( c in children ) {
			var node = Std.downcast(c, HierarchicalWorld);
			if ( node == null )
				continue;
			node.unlockAt(x, y);
		}
	}

	public function unlockAll() {
		locked = false;
		for ( c in children ) {
			var node = Std.downcast(c, HierarchicalWorld);
			if ( node == null )
				continue;
			node.unlockAll();
		}
	}

	public function getRoot() : h3d.scene.HierarchicalWorld {
		var root : h3d.scene.Object = this;
		while ( Std.isOfType(root.parent, HierarchicalWorld) )
			root = root.parent;
		return cast root;
	}
}