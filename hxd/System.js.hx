package hxd;

import js.html.VisibilityState;

enum Platform {
	IOS;
	Android;
	WebGL;
	PC;
	Console;
	FlashPlayer;
}

enum SystemValue {
	IsTouch;
	IsWindowed;
	IsMobile;
}

class System {

	public static var width(get,never) : Int;
	public static var height(get, never) : Int;
	public static var lang(get, never) : String;
	public static var platform(get, never) : Platform;
	public static var screenDPI(get,never) : Float;
	public static var setCursor = setNativeCursor;
	public static var allowTimeout(get, set) : Bool;
	public static var deltaTime:Float = 0.0;

	static var lastFrameStartTime:Float = 0.0;

	public static function timeoutTick() : Void {
	}

	static var loopFunc : Void -> Void;

	// JS
	static var loopInit = false;
	static var currentNativeCursor:hxd.Cursor;
	static var currentCustomCursor:hxd.Cursor.CustomCursor;

	/** If greater than 0, this will reduce loop framerate to reduce CPU usage **/
	public static var fpsLimit = -1;
	static var lastRqfId = 0;

	public static function getCurrentLoop() : Void -> Void {
		return loopFunc;
	}

	public static function setLoop( f : Void -> Void ) : Void {
		lastFrameStartTime = js.Browser.window.performance.now();
		if( !loopInit ) {
			loopInit = true;
			browserLoop();
		}
		loopFunc = f;
	}

	public static var gameHasFocus(default, null): Bool;

	// static function browserLoop() {
	// 	if( js.Browser.supported ) {
	// 		var window : Dynamic = js.Browser.window;
	// 		var rqf : Dynamic = window.requestAnimationFrame ||
	// 			window.webkitRequestAnimationFrame ||
	// 			window.mozRequestAnimationFrame;
	// 		if( fpsLimit>0 ) //Should we use setTimouout always?
	// 			js.Browser.window.setTimeout( ()->rqf(browserLoop), 1000/fpsLimit );
	// 		else
	// 			rqf(browserLoop);
	// 	} else {
	// 		#if (nodejs && hxnodejs)
	// 		js.node.Timers.setTimeout(browserLoop, 0);
	// 		#else
	// 		throw "Cannot use browserLoop without Browser support nor defining nodejs + hxnodejs";
	// 		#end
	// 	}
	// 	if( loopFunc != null ) loopFunc();
	// }

	static function browserLoop(?loopDelta:Float) {
		//js.html.Console.log("LOOP");
		lastRqfId = 0;

		var currentTime = (loopDelta != null ? loopDelta : js.Browser.window.performance.now());

		System.deltaTime = (currentTime - lastFrameStartTime) / 1000.0;
		
		lastFrameStartTime = currentTime;
		
		if (loopFunc != null) loopFunc();
		
		if(gameHasFocus && fpsLimit < 0) {
			lastRqfId = js.Browser.window.requestAnimationFrame(browserLoop);
		} else {
			var targetFPS = (fpsLimit > 0) ? fpsLimit : 60;
			var targetFrameTime = 1000 / targetFPS;
			var frameTime = System.deltaTime;
			var nextDelay = Math.max(0, targetFrameTime - frameTime);
			js.Browser.window.setTimeout(browserLoop, Std.int(nextDelay));
		}
		
	}

	public static function start( callb : Void -> Void ) : Void {
		callb();
	}

	public static function setNativeCursor( c : Cursor ) : Void {
		if( currentNativeCursor != null && c.equals(currentNativeCursor) )
			return;
		currentNativeCursor = c;
		currentCustomCursor = null;
		var canvas = @:privateAccess hxd.Window.getInstance().canvas;
		if( canvas != null ) {
			canvas.style.cursor = switch( c ) {
			case Default: "default";
			case Button: "pointer";
			case Move: "move";
			case TextInput: "text";
			case Hide: "none";
			case Callback(_): throw "assert";
			case Custom(cur):
				if ( cur.alloc == null ) {
					cur.alloc = new Array();
					for ( frame in cur.frames ) {
						cur.alloc.push("url(\"" + frame.toNative().canvas.toDataURL("image/png") + "\") " + cur.offsetX + " " + cur.offsetY + ", default");
					}
				}
				if ( cur.frames.length > 1 ) {
					currentCustomCursor = cur;
					cur.reset();
				}
				cur.alloc[cur.frameIndex];
			};
		}
	}

	public static function getDeviceName() : String {
		return "Unknown";
	}

	public static function getDefaultFrameRate() : Float {
		return 60.;
	}

	public static function getValue( s : SystemValue ) : Bool {
		return switch( s ) {
		case IsWindowed: true;
		case IsTouch: platform==Android || platform==IOS;
		case IsMobile: platform==Android || platform==IOS;
		default: false;
		}
	}

	public static function exit() : Void {
	}

	public static function openURL( url : String ) : Void {
		js.Browser.window.open(url, '_blank');
	}

	static function updateCursor() : Void {
		if ( currentCustomCursor != null ) {
			var change = currentCustomCursor.update(hxd.Timer.elapsedTime);
			if ( change != -1 ) {
				var canvas = @:privateAccess hxd.Window.getInstance().canvas;
				if ( canvas != null ) {
					canvas.style.cursor = currentCustomCursor.alloc[change];
				}
			}
		}
	}

	public static function getClipboardText() : String {
		#if (hide && editor)
		return nw.Clipboard.get().get(Text);
		#end
		return null;
	}

	public static function setClipboardText(text:String) : Bool {
		#if (hide && editor)
		nw.Clipboard.get().set({ data: text, type: nw.Clipboard.ClipboardType.Text });
		return true;
		#end
		return false;
	}

	public static function getLocale() : String {
		return js.Browser.navigator.language + "_" + js.Browser.navigator.language.toUpperCase();
	}

	// getters

	static function get_width() : Int return Math.round(js.Browser.document.body.clientWidth * js.Browser.window.devicePixelRatio);
	static function get_height() : Int return Math.round(js.Browser.document.body.clientHeight  * js.Browser.window.devicePixelRatio);
	static function get_lang() : String return js.Browser.navigator.language;
	static function get_platform() : Platform {
		var ua = js.Browser.navigator.userAgent.toLowerCase();
		if( ua.indexOf("android")>=0 )
			return Android;
		else if( ua.indexOf("ipad")>=0 || ua.indexOf("iphone")>=0 || ua.indexOf("ipod")>=0 )
			return IOS;
		else
			return PC;
	}
	static function get_screenDPI() : Int return 72;
	static function get_allowTimeout() return false;
	static function set_allowTimeout(b) return false;

	static function __init__() : Void {
		haxe.MainLoop.add(updateCursor, -1);

		js.Browser.document.addEventListener("visibilitychange", function() {
			//js.html.Console.log("VISIBILITY IS NOW " + js.Browser.document.visibilityState);
			gameHasFocus = js.Browser.document.visibilityState == VisibilityState.VISIBLE;
			if(lastRqfId > 0) {
				//Switch over to setTimeout loop
				js.Browser.window.cancelAnimationFrame(lastRqfId);
				lastRqfId = 0;
				js.Browser.window.setTimeout(browserLoop, 0);
			}
		});
		gameHasFocus = js.Browser.document.visibilityState == VisibilityState.VISIBLE;
	}

}
