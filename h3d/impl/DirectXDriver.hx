package h3d.impl;

#if hldx

import h3d.impl.Driver;
import dx.Driver;
import h3d.mat.Pass;

private class ShaderContext {
	public var shader : Shader;
	public var globalsSize : Int;
	public var paramsSize : Int;
	public var texturesCount : Int;
	public var globals : dx.Resource;
	public var params : dx.Resource;
	public function new(shader) {
		this.shader = shader;
	}
}

private class CompiledShader {
	public var vertex : ShaderContext;
	public var fragment : ShaderContext;
	public var layout : Layout;
	public var inputs : Array<String>;
	public var offsets : Array<Int>;
	public function new() {
	}
}

enum PipelineKind {
	Vertex;
	Pixel;
}

class PipelineState {
	public var kind : PipelineKind;
	public var samplers = new hl.NativeArray<SamplerState>(64);
	public var samplerBits = new Array<Int>();
	public var resources = new hl.NativeArray<ShaderResourceView>(64);
	public var buffers = new hl.NativeArray<dx.Resource>(16);
	public function new(kind) {
		this.kind = kind;
		for(i in 0...64 ) samplerBits[i] = -1;
	}
}

class DirectXDriver extends h3d.impl.Driver {

	var driver : DriverInstance;
	var shaders : Map<Int,CompiledShader>;
	var box = new dx.Resource.ResourceBox();
	var strides : Array<Int> = [];
	var offsets : Array<Int> = [];
	var currentShader : CompiledShader;
	var currentIndex : IndexBuffer;
	var defaultTarget : RenderTargetView;
	var currentTargets = new hl.NativeArray<RenderTargetView>(16);
	var viewport : hl.BytesAccess<hl.F32> = new hl.Bytes(6 * 4);
	var depthView : DepthStencilView;
	var vertexShader = new PipelineState(Vertex);
	var pixelShader = new PipelineState(Pixel);
	var currentVBuffers = new hl.NativeArray<dx.Resource>(16);
	var frame : Int;
	var currentMaterialBits = -1;

	var depthStates : Map<Int,DepthStencilState> = new Map();
	var blendStates : Map<Int,BlendState> = new Map();
	var rasterStates : Map<Int,RasterState> = new Map();
	var samplerStates : Map<Int,SamplerState> = new Map();
	var currentDepthState : DepthStencilState;
	var currentBlendState : BlendState;
	var currentRasterState : RasterState;
	var blendFactors : hl.BytesAccess<hl.F32> = new hl.Bytes(4 * 4);

	public function new() {
		shaders = new Map();
		var win = @:privateAccess dx.Window.windows[0];
		driver = Driver.create(win);
		if( driver == null ) throw "Failed to initialize DirectX driver";
		Driver.iaSetPrimitiveTopology(TriangleList);

		var width = win.width;
		var height = win.height;

		var depthDesc = new Texture2dDesc();
		depthDesc.width = width;
		depthDesc.height = height;
		depthDesc.format = D24_UNORM_S8_UINT;
		depthDesc.bind = DepthStencil;
		var depth = Driver.createTexture2d(depthDesc);
		depthView = Driver.createDepthStencilView(depth,depthDesc.format);

		var buf = Driver.getBackBuffer();
		defaultTarget = Driver.createRenderTargetView(buf);
		buf.release();

		viewport[2] = win.width;
		viewport[3] = win.height;
		viewport[5] = 1.;
		Driver.rsSetViewports(1, viewport);

		currentTargets[0] = defaultTarget;
		Driver.omSetRenderTargets(1, currentTargets, depthView);
	}

	override function begin(frame:Int) {
		this.frame = frame;
	}

	override function isDisposed() {
		return false;
	}

	override function init( onCreate : Bool -> Void, forceSoftware = false ) {
		haxe.Timer.delay(onCreate.bind(false), 1);
	}

	override function clear(?color:h3d.Vector, ?depth:Float, ?stencil:Int) {
		if( color != null )
			Driver.clearColor(currentTargets[0], color.r, color.g, color.b, color.a);
		if( depth != null || stencil != null )
			Driver.clearDepthStencilView(depthView, depth, stencil);
	}

	override function getDriverName(details:Bool) {
		var desc = "DirectX" + Driver.getSupportedVersion();
		if( details ) desc += " " + Driver.getDeviceName();
		return desc;
	}

	override function present() {
		Driver.present();
	}

	override function allocVertexes(m:ManagedBuffer):VertexBuffer {
		var res = dx.Driver.createBuffer(m.size * m.stride * 4, Default, VertexBuffer, None, None, 0, null);
		if( res == null ) return null;
		return { res : res, count : m.size, stride : m.stride };
	}

	override function allocIndexes( count : Int ) : IndexBuffer {
		var res = dx.Driver.createBuffer(count << 1, Default, IndexBuffer, None, None, 0, null);
		return { res : res, count : count };
	}

	override function allocTexture(t:h3d.mat.Texture):Texture {
		var desc = new Texture2dDesc();
		desc.width = t.width;
		desc.height = t.height;
		desc.format = R8G8B8A8_UNORM;
		desc.usage = Default;
		desc.bind = ShaderResource;
		var tex = Driver.createTexture2d(desc);

		var vdesc = new ShaderResourceViewDesc();
		vdesc.format = desc.format;
		vdesc.dimension = Texture2D;
		vdesc.start = 0; // top mip level
		vdesc.count = -1; // all mip levels
		var view = Driver.createShaderResourceView(tex, vdesc);
		return { res : tex, view : view };
	}

	override function disposeTexture( t : h3d.mat.Texture ) {
		var tt = t.t;
		if( tt == null ) return;
		t.t = null;
		tt.view.release();
		tt.res.release();
	}

	override function disposeVertexes(v:VertexBuffer) {
		v.res.release();
	}

	override function disposeIndexes(i:IndexBuffer) {
		i.res.release();
	}

	override function uploadIndexBuffer(i:IndexBuffer, startIndice:Int, indiceCount:Int, buf:hxd.IndexBuffer, bufPos:Int) {
		if( startIndice > 0 || indiceCount != i.count ) throw "TODO";
		i.res.updateSubresource(0, null, hl.Bytes.getArray(buf.getNative()).offset(bufPos<<1), 0, 0);
	}

	override function uploadIndexBytes(i:IndexBuffer, startIndice:Int, indiceCount:Int, buf:haxe.io.Bytes, bufPos:Int) {
		if( startIndice > 0 || indiceCount != i.count ) throw "TODO";
		i.res.updateSubresource(0, null, @:privateAccess buf.b.offset(bufPos << 1), 0, 0);
	}

	override public function uploadVertexBuffer(v:VertexBuffer, startVertex:Int, vertexCount:Int, buf:hxd.FloatBuffer, bufPos:Int) {
		if( startVertex > 0 || vertexCount != v.count ) throw "TODO";
		v.res.updateSubresource(0, null, hl.Bytes.getArray(buf.getNative()).offset(bufPos<<2), 0, 0);
	}

	override public function uploadVertexBytes(v:VertexBuffer, startVertex:Int, vertexCount:Int, buf:haxe.io.Bytes, bufPos:Int) {
		if( startVertex > 0 || vertexCount != v.count ) throw "TODO";
		v.res.updateSubresource(0, null, @:privateAccess buf.b.offset(bufPos << 2), 0, 0);
	}

	override function uploadTextureBitmap(t:h3d.mat.Texture, bmp:hxd.BitmapData, mipLevel:Int, side:Int) {
		var pixels = bmp.getPixels();
		uploadTexturePixels(t, pixels, mipLevel, side);
		pixels.dispose();
	}

	override function uploadTexturePixels(t:h3d.mat.Texture, pixels:hxd.Pixels, mipLevel:Int, side:Int) {
		if( mipLevel != 0 || side != 0 ) throw "TODO";
		pixels.convert(RGBA);
		t.t.res.updateSubresource(0, null, pixels.bytes, pixels.width << 2, 0);
	}

	override public function selectMaterial(pass:h3d.mat.Pass) {
		var bits = @:privateAccess pass.bits;
		if( bits == currentMaterialBits )
			return;

		var depthBits = bits & (Pass.depthWrite_mask | Pass.depthTest_mask);
		if( pass.stencil != null ) throw "TODO";
		var depth = depthStates.get(depthBits);
		if( depth == null ) {
			var cmp = Pass.getDepthTest(bits);
			var desc = new DepthStencilDesc();
			desc.depthEnable = cmp != 0;
			desc.depthFunc = COMPARE[cmp];
			desc.depthWrite = Pass.getDepthWrite(bits) != 0;
			depth = Driver.createDepthStencilState(desc);
			depthStates.set(depthBits, depth);
		}
		if( depth != currentDepthState ) {
			currentDepthState = depth;
			Driver.omSetDepthStencilState(depth);
		}

		var rasterBits = bits & (Pass.culling_mask);
		var raster = rasterStates.get(rasterBits);
		if( raster == null ) {
			var desc = new RasterizerDesc();
			desc.fillMode = Solid;
			desc.cullMode = CULL[Pass.getCulling(bits)];
			if( pass.culling == Both ) throw "Culling:Both Not supported in DirectX";
			desc.depthClipEnable = true;
			raster = Driver.createRasterizerState(desc);
			rasterStates.set(rasterBits, raster);
		}
		if( raster != currentRasterState ) {
			currentRasterState = raster;
			Driver.rsSetState(raster);
		}

		var blendBits = bits & (Pass.blendSrc_mask | Pass.blendDst_mask | Pass.blendAlphaSrc_mask | Pass.blendAlphaDst_mask | Pass.blendOp_mask | Pass.blendAlphaOp_mask | Pass.colorMask_mask);
		var blend = blendStates.get(blendBits);
		if( blend == null ) {
			var desc = new RenderTargetBlendDesc();
			desc.srcBlend = BLEND[Pass.getBlendSrc(bits)];
			desc.destBlend = BLEND[Pass.getBlendDst(bits)];
			desc.srcBlendAlpha = BLEND[Pass.getBlendAlphaSrc(bits)];
			desc.destBlendAlpha = BLEND[Pass.getBlendAlphaDst(bits)];
			desc.blendOp = BLEND_OP[Pass.getBlendOp(bits)];
			desc.blendOpAlpha = BLEND_OP[Pass.getBlendAlphaOp(bits)];
			desc.renderTargetWriteMask = Pass.getColorMask(bits);
			desc.blendEnable = !(desc.srcBlend == One && desc.srcBlendAlpha == One && desc.destBlend == Zero && desc.destBlendAlpha == Zero && desc.blendOp == Add && desc.blendOpAlpha == Add);
			var tmp = new hl.NativeArray(1);
			tmp[0] = desc;
			blend = Driver.createBlendState(false, false, tmp, 1);
			blendStates.set(blendBits, blend);
		}
		if( blend != currentBlendState ) {
			currentBlendState = blend;
			Driver.omSetBlendState(blend, blendFactors, -1);
		}
	}

	function compileShader( shader : hxsl.RuntimeShader.RuntimeShaderData, compileOnly = false ) {
		var h = new hxsl.HlslOut();
		var source = h.run(shader.data);
		var bytes = try dx.Driver.compileShader(source, "", "main", shader.vertex?"vs_5_0":"ps_5_0", OptimizationLevel3) catch( err : String ) {
			err = ~/^\(([0-9]+),([0-9]+)-([0-9]+)\)/gm.map(err, function(r) {
				var line = Std.parseInt(r.matched(1));
				var char = Std.parseInt(r.matched(2));
				var end = Std.parseInt(r.matched(3));
				return "\n<< " + source.split("\n")[line - 1].substr(char-1,end - char + 1) +" >>";
			});
			throw "Shader compilation error " + err + "\n\nin\n\n" + source;
		}
		if( compileOnly )
			return { s : null, bytes : bytes };
		var s = shader.vertex ? Driver.createVertexShader(bytes) : Driver.createPixelShader(bytes);
		if( s == null )
			throw "Failed to create shader\n" + source;
		var ctx = new ShaderContext(s);
		ctx.globalsSize = shader.globalsSize;
		ctx.paramsSize = shader.paramsSize;
		ctx.texturesCount = shader.textures2DCount + shader.texturesCubeCount;
		ctx.globals = dx.Driver.createBuffer(shader.globalsSize * 16, Dynamic, ConstantBuffer, CpuWrite, None, 0, null);
		ctx.params = dx.Driver.createBuffer(shader.paramsSize * 16, Dynamic, ConstantBuffer, CpuWrite, None, 0, null);
		return { s : ctx, bytes : bytes };
	}

	override function getNativeShaderCode( shader : hxsl.RuntimeShader ) {
		var v = compileShader(shader.vertex, true).bytes;
		var f = compileShader(shader.fragment, true).bytes;
		return Driver.disassembleShader(v, None, null) + "\n" + Driver.disassembleShader(f, None, null);
		//return "// vertex:\n" + new hxsl.HlslOut().run(shader.vertex.data) + "// fragment:\n" + new hxsl.HlslOut().run(shader.fragment.data);
	}

	override function selectShader(shader:hxsl.RuntimeShader) {
		var s = shaders.get(shader.id);
		if( s == null ) {
			s = new CompiledShader();
			var vertex = compileShader(shader.vertex);
			s.vertex = vertex.s;
			s.fragment = compileShader(shader.fragment).s;
			s.inputs = [];
			s.offsets = [];

			var layout = [], offset = 0;
			for( v in shader.vertex.data.vars )
				if( v.kind == Input ) {
					var e = new LayoutElement();
					e.semanticName = @:privateAccess v.name.toUtf8();
					e.inputSlot = layout.length;
					e.format = switch( v.type ) {
					case TFloat: R32_FLOAT;
					case TVec(2, VFloat): R32G32_FLOAT;
					case TVec(3, VFloat): R32G32B32_FLOAT;
					case TVec(4, VFloat): R32G32B32A32_FLOAT;
					case TBytes(4): R8G8B8A8_UINT;
					default:
						throw "Unsupported input type " + hxsl.Ast.Tools.toString(v.type);
					};
					e.inputSlotClass = PerVertexData;
					layout.push(e);
					s.offsets.push(offset);
					s.inputs.push(v.name);

					var size = switch( v.type ) {
					case TVec(n, _): n;
					case TBytes(n): n;
					case TFloat: 1;
					default: throw "assert " + v.type;
					}

					trace(v.name, offset, size);
					offset += size;
				}

			var n = new hl.NativeArray(layout.length);
			for( i in 0...layout.length )
				n[i] = layout[i];
			s.layout = Driver.createInputLayout(n, vertex.bytes, vertex.bytes.length);
			if( s.layout == null )
				throw "Failed to create input layout";
			shaders.set(shader.id, s);
		}
		if( s == currentShader )
			return false;
		currentShader = s;
		dx.Driver.vsSetShader(s.vertex.shader);
		dx.Driver.psSetShader(s.fragment.shader);
		dx.Driver.iaSetInputLayout(s.layout);
		return true;
	}

	override function getShaderInputNames():Array<String> {
		return currentShader.inputs;
	}

	override function selectBuffer(buffer:Buffer) {
		var vbuf = @:privateAccess buffer.buffer.vbuf;
		var start = -1, max = -1, position = 0;
		for( i in 0...currentShader.inputs.length ) {
			if( currentVBuffers[i] != vbuf.res || offsets[i] != currentShader.offsets[i] << 2 ) {
				currentVBuffers[i] = vbuf.res;
				strides[i] = buffer.buffer.stride << 2;
				offsets[i] = currentShader.offsets[i] << 2;
				if( start < 0 ) start = i;
				max = i;
			}
		}
		if( max >= 0 )
			Driver.iaSetVertexBuffers(start, max - start + 1, currentVBuffers.getRef().offset(start), hl.Bytes.getArray(strides).offset(start << 2), hl.Bytes.getArray(offsets).offset(start << 2));
	}

	override function selectMultiBuffers(bl:Buffer.BufferOffset) {
		var index = 0;
		var start = -1, max = -1;
		while( bl != null ) {
			var vbuf = @:privateAccess bl.buffer.buffer.vbuf;
			if( currentVBuffers[index] != vbuf.res || offsets[index] != bl.offset << 2 ) {
				currentVBuffers[index] = vbuf.res;
				offsets[index] = bl.offset << 2;
				strides[index] = bl.buffer.buffer.stride << 2;
				if( start < 0 ) start = index;
				max = index;
			}
			index++;
			bl = bl.next;
		}
		if( max >= 0 )
			Driver.iaSetVertexBuffers(start, max - start + 1, currentVBuffers.getRef().offset(start), hl.Bytes.getArray(strides).offset(start << 2), hl.Bytes.getArray(offsets).offset(start << 2));
	}

	function uploadShaderBuffer( sbuffer : dx.Resource, buffer : haxe.ds.Vector<hxd.impl.Float32>, size : Int ) {
		if( size == 0 ) return;
		var ptr = sbuffer.map(0, WriteDiscard, true);
		if( ptr == null ) throw "Can't map buffer " + sbuffer;
		ptr.blit(0, hl.Bytes.getArray(buffer.toData()), 0, size * 16);
		sbuffer.unmap(0);
	}

	override function uploadShaderBuffers(buffers:h3d.shader.Buffers, which:h3d.shader.Buffers.BufferKind) {
		uploadBuffers(vertexShader, currentShader.vertex, buffers.vertex, which);
		uploadBuffers(pixelShader, currentShader.fragment, buffers.fragment, which);
	}

	function uploadBuffers( state : PipelineState, shader : ShaderContext, buffers : h3d.shader.Buffers.ShaderBuffers, which : h3d.shader.Buffers.BufferKind ) {
		switch( which ) {
		case Globals:
			if( shader.globalsSize > 0 ) {
				uploadShaderBuffer(shader.globals, buffers.globals, shader.globalsSize);
				if( state.buffers[0] != shader.globals ) {
					state.buffers[0] = shader.globals;
					switch( state.kind ) {
					case Vertex:
						Driver.vsSetConstantBuffers(0, 1, state.buffers);
					case Pixel:
						Driver.psSetConstantBuffers(0, 1, state.buffers);
					}
				}
			}
		case Params:
			if( shader.paramsSize > 0 ) {
				uploadShaderBuffer(shader.params, buffers.params, shader.paramsSize);
				if( state.buffers[1] != shader.params ) {
					state.buffers[1] = shader.params;
					switch( state.kind ) {
					case Vertex:
						Driver.vsSetConstantBuffers(1, 1, state.buffers.getRef().offset(1));
					case Pixel:
						Driver.psSetConstantBuffers(1, 1, state.buffers.getRef().offset(1));
					}
				}
			}
		case Textures:
			var start = -1, max = -1;
			var sstart = -1, smax = -1;
			for( i in 0...shader.texturesCount ) {
				var t = buffers.tex[i];
				if( t == null || t.isDisposed() ) {
					var color = h3d.mat.Defaults.loadingTextureColor;
					t = h3d.mat.Texture.fromColor(color,(color>>>24)/255);
				}
				if( t != null && t.t == null && t.realloc != null ) {
					t.alloc();
					t.realloc();
				}
				t.lastFrame = frame;

				var view = t.t.view;
				if( view == state.resources[i] ) continue;

				state.resources[i] = view;
				max = i;
				if( start < 0 ) start = i;

				var bits = @:privateAccess t.bits;
				if( bits != state.samplerBits[i] ) {
					var ss = samplerStates.get(bits);
					if( ss == null ) {
						var desc = new SamplerDesc();
						desc.filter = FILTER[t.mipMap.getIndex()][t.filter.getIndex()];
						desc.addressU = desc.addressV = desc.addressW = WRAP[t.wrap.getIndex()];
						if( t.mipMap == None ) {
							desc.minLod = desc.maxLod = 0;
						} else {
							desc.minLod = 0;
							desc.maxLod = 1e30;
						}
						ss = Driver.createSamplerState(desc);
						samplerStates.set(bits, ss);
					}
					state.samplerBits[i] = bits;
					state.samplers[i] = ss;
					smax = i;
					if( sstart < 0 ) sstart = i;
				}
			}
			switch( state.kind) {
			case Vertex:
				if( max >= 0 ) Driver.vsSetShaderResources(start, max - start + 1, state.resources.getRef().offset(start));
				if( smax >= 0 ) Driver.vsSetSamplers(sstart, smax - sstart + 1, state.samplers.getRef().offset(sstart));
			case Pixel:
				if( max >= 0 ) Driver.psSetShaderResources(start, max - start + 1, state.resources.getRef().offset(start));
				if( smax >= 0 ) Driver.psSetSamplers(sstart, smax - sstart + 1, state.samplers.getRef().offset(sstart));
			}
		}
	}

	override function draw(ibuf:IndexBuffer, startIndex:Int, ntriangles:Int) {
		if( currentIndex != ibuf ) {
			currentIndex = ibuf;
			dx.Driver.iaSetIndexBuffer(ibuf.res,false,0);
		}
		dx.Driver.drawIndexed(ntriangles * 3, startIndex, 0);
	}

	static var COMPARE : Array<ComparisonFunc> = [
		Always,
		Never,
		Equal,
		NotEqual,
		Greater,
		GreaterEqual,
		Less,
		LessEqual
	];

	static var CULL : Array<CullMode> = [
		None,
		Back,
		Front,
	];

	static var BLEND : Array<Blend> = [
		One,
		Zero,
		SrcAlpha,
		SrcColor,
		DestAlpha,
		DestColor,
		InvSrcAlpha,
		InvSrcColor,
		InvDestAlpha,
		InvDestColor,
		Src1Color,
		Src1Alpha,
		InvSrc1Color,
		InvSrc1Alpha,
		SrcAlphaSat,
		// BlendFactor/InvBlendFactor : not supported by Heaps for now
	];

	static var BLEND_OP : Array<BlendOp> = [
		Add,
		Subtract,
		RevSubstract,
		// Min / Max : not supported by Heaps for now
	];

	static var FILTER : Array<Array<Filter>> = [
		[MinMagMipPoint,MinMagMipLinear],
		[MinMagMipPoint,MinMagLinearMipPoint],
		[MinMagPointMipLinear, MinMagMipLinear],
		// Anisotropic , Comparison, Minimum, Maximum
	];

	static var WRAP : Array<AddressMode> = [
		Clamp,
		Wrap,
		//Mirror , Border , MirrorOnce
	];
}

#end
