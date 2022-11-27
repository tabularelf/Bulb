/// @param tileset
/// @param [checkForTag=true]

function __BulbClassTileset(_tileset, _checkForTag = true) constructor
{
    global.__bulbTilesetDict[$ _tileset] = self;
    
    __tileset = _tileset;
    __hash    = undefined;
    
    layer_set_target_room(0);
    var _layer   = layer_create(0);
    var _tilemap = layer_tilemap_create(_layer, 0, 0, _tileset, 1, 1);
    
    __tileWidth  = tilemap_get_tile_width(_tilemap);
    __tileHeight = tilemap_get_tile_height(_tilemap);
    
    layer_tilemap_destroy(_tilemap);
    layer_destroy(_layer);
    layer_reset_target_room();
    
    var _tilesetTexture = tileset_get_texture(_tileset);
    var _tilesetUVs     = tileset_get_uvs(_tileset);
    
    __textureWidth   = (_tilesetUVs[2] - _tilesetUVs[0]) / texture_get_texel_width(_tilesetTexture);
    __textureHeight  = (_tilesetUVs[3] - _tilesetUVs[1]) / texture_get_texel_height(_tilesetTexture);
    
    __tilesWide = __textureWidth  / (__tileWidth  + 4);
    __tilesHigh = __textureHeight / (__tileHeight + 4);
    
    __tileDict = undefined;
    
    if (_checkForTag) __EnsureTag();
    
    
    
    static __GetTileDictionary = function()
    {
        if (__tileDict == undefined)
        {
            if (__DiskCheck()) __DiskLoad();
        }
        
        if (__tileDict == undefined)
        {
            __tileDict = {};
            
            var _buffer = __GetBuffer();
            
            //We'll likely need the hash later so we can save a bit of time by calculating it now
            if (BULB_DISK_CACHE && (__BULB_BUILD_TYPE == "run")) __GetHash(_buffer);
            
            if (BULB_VERBOSE) var _t = get_timer();
            var _trace = __BulbTraceBuffer(_buffer, __textureWidth, __textureHeight, 0, 0, 0, false, 1/255, false);
            if (BULB_VERBOSE) __BulbTrace("Tracing ", tileset_get_name(__tileset), " buffer took ", (get_timer() - _t)/1000, "ms");
            buffer_delete(_buffer);
            
            //Sort the traced loops into tile indexes
            var _extTileWidth  = 4 + __tileWidth;
            var _extTileHeight = 4 + __tileHeight;
            
            var _i = 0;
            repeat(array_length(_trace))
            {
                var _loop = _trace[_i];
                
                //Figure out which tile this is for using the first point
                var _tileX = _loop[0] div _extTileWidth;
                var _tileY = _loop[1] div _extTileHeight;
                var _tileIndex = _tileX + _tileY*__tilesWide;
                
                //Adjust the position of all points in the loop relative to the top-left corner of the tile
                var _x = 2 + _tileX*_extTileWidth;
                var _y = 2 + _tileY*_extTileHeight;
                
                var _j = 0;
                repeat(array_length(_loop) div 2)
                {
                    _loop[@ _j  ] -= _x;
                    _loop[@ _j+1] -= _y;
                    
                    _j += 2;
                }
                
                //Push this loop into a per-tile array
                var _tileLoopArray = __tileDict[$ _tileIndex];
                if (!is_array(_tileLoopArray))
                {
                    _tileLoopArray = [];
                    __tileDict[$ _tileIndex] = _tileLoopArray;
                }
                
                array_push(_tileLoopArray, _loop);
                
                ++_i;
            }
            
            __DiskSave();
        }
        
        return __trace;
    }
    
    static __DiskCheck = function()
    {
        if (!BULB_DISK_CACHE) return false;
        
        if (__onDisk == undefined)
        {
            __onDisk = variable_struct_exists(global.__bulbCacheDict, tileset_get_name(__tileset));
        }
        
        return __onDisk;
    }
    
    static __DiskLoad = function()
    {
        if (!BULB_DISK_CACHE) return;
        if (!__DiskCheck()) return;
        
        if (BULB_VERBOSE) var _t = get_timer();
        
        var _buffer = global.__bulbCacheBuffer;
        var _oldTell = buffer_tell(_buffer);
        
        var _bufferPos = global.__bulbCacheDict[$ tileset_get_name(__tileset)];
        buffer_seek(_buffer, buffer_seek_start, _bufferPos);
        
        var _expectedFinalTell = _bufferPos + buffer_read(_buffer, buffer_u64);
        
        var _diskName = buffer_read(_buffer, buffer_string);
        if (_diskName != tileset_get_name(__tileset))
        {
            if (BULB_VERBOSE) __BulbTrace("Name in cache (", _diskName, ") doesn't match expected name (", tileset_get_name(__tileset), ")");
            
            __onDisk = false;
            buffer_seek(_buffer, buffer_seek_start, _oldTell);
            return;
        }
        
        var _diskHash  = buffer_read(_buffer, buffer_string);
        var _buildDate = buffer_read(_buffer, buffer_f64);
        
        if (__BULB_BUILD_TYPE == "run")
        {
            if (__GetHash() != _diskHash)
            {
                if (BULB_VERBOSE) __BulbTrace("Hash for ", tileset_get_name(__tileset), " (", __GetHash(), ") doesn't match hash on disk (", _diskHash, ")");
                
                __onDisk = false;
                buffer_seek(_buffer, buffer_seek_start, _oldTell);
                return;
            }
        }
        else
        {
            if (GM_build_date != _buildDate)
            {
                if (BULB_VERBOSE) __BulbTrace("Current build date for ", tileset_get_name(__tileset), " (", string_format(GM_build_date, 0, 10), ") doesn't match build date on disk (", string_format(_buildDate, 0, 10), ")");
                
                __onDisk = false;
                buffer_seek(_buffer, buffer_seek_start, _oldTell);
                return;
            }
        }
        
        // ------------------------------------------------------------
        
        __tileDict = {};
        
        var _tileCount = buffer_read(_buffer, buffer_u64);
        var _i = 0;
        repeat(_tileCount)
        {
            var _tileIndex = buffer_read(_buffer, buffer_u64);
            
            var _loopCount = buffer_read(_buffer, buffer_u64);
            var _loopArray = array_create(_loopCount, undefined);
            
            __tileDict[$ _tileIndex] = _loopArray;
            
            var _j = 0;
            repeat(_loopCount)
            {
                var _loopLength = buffer_read(_buffer, buffer_u64);
                var _loop = array_create(_loopLength, undefined);
                _loopArray[@ _j] = _loop;
                
                var _k = 0;
                repeat(_loopLength)
                {
                    _loop[@ _k] = buffer_read(_buffer, buffer_s16);
                    ++_k;
                }
                
                ++_j;
            }
            
            ++_i;
        }
        
        // ------------------------------------------------------------
        
        if (buffer_tell(_buffer) != _expectedFinalTell)
        {
            if (BULB_VERBOSE) __BulbTrace("Warning! Final buffer position (", buffer_tell(_buffer), ") did not match expected (", _expectedFinalTell, ")");
            
            __trace = undefined;
            
            __onDisk = false;
            buffer_seek(_buffer, buffer_seek_start, _oldTell);
            return;
        }
        
        if (BULB_VERBOSE) __BulbTrace("Loading trace of ", tileset_get_name(__tileset), " from disk cache took ", (get_timer() - _t)/1000, "ms");
        
        buffer_seek(_buffer, buffer_seek_start, _oldTell);
        return __trace;
    }
    
    static __DiskSave = function()
    {
        if (!BULB_DISK_CACHE) return;
        
        __onDisk = true;
        
        var _buffer = global.__bulbCacheBuffer;
        
        buffer_seek(_buffer, buffer_seek_relative, -8);
        
        var _byteSizePosition = buffer_tell(_buffer);
        buffer_write(_buffer, buffer_u64, 0);
        
        buffer_write(_buffer, buffer_string, tileset_get_name(__tileset));
        buffer_write(_buffer, buffer_string, (__BULB_BUILD_TYPE == "run")? __GetHash() : "<undefined>");
        buffer_write(_buffer, buffer_f64,    GM_build_date);
        
        // ------------------------------------------------------------
        
        var _tileIndexArray = variable_struct_get_names(__tileDict);
        buffer_write(_buffer, buffer_u64, array_length(_tileIndexArray));
        
        var _i = 0;
        repeat(array_length(_tileIndexArray))
        {
            var _tileIndex = _tileIndexArray[_i];
            buffer_write(_buffer, buffer_u64, real(_tileIndex));
            
            var _tileLoopArray = _tileIndexArray[_tileIndex];
            buffer_write(_buffer, buffer_u64, array_length(_tileLoopArray));
            
            var _j = 0;
            repeat(array_length(_tileLoopArray))
            {
                var _loop = _tileLoopArray[_j];
                buffer_write(_buffer, buffer_u64, array_length(_loop));
                
                var _k = 0;
                repeat(array_length(_loop))
                {
                    buffer_write(_buffer, buffer_s16, _loop[_k]);
                    ++_k;
                }
                
                ++_j;
            };
            
            ++_i;
        }
        
        // ------------------------------------------------------------
        
        var _byteSize = buffer_tell(_buffer) - _byteSizePosition;
        buffer_poke(_buffer, _byteSizePosition, buffer_u64, _byteSize);
        buffer_write(_buffer, buffer_u64, 0);
        
        if (!global.__bulbCachePauseSave) buffer_save_ext(_buffer, __BULB_DISK_CACHE_NAME, 0, buffer_tell(_buffer));
    }
    
    static __GetHash = function(_buffer = undefined)
    {
        if (__hash == undefined)
        {
            var _destroyBuffer = false;
            
            if (_buffer == undefined)
            {
                _buffer = __GetBuffer();
                _destroyBuffer = true;
            }
            
            __hash = buffer_md5(_buffer, 0, buffer_get_size(_buffer));
            
            if (_destroyBuffer) buffer_delete(_buffer);
        }
        
        return __hash;
    }
    
    static __GetBuffer = function()
    {
        var _extTileWidth  = 4 + __tileWidth;
        var _extTileHeight = 4 + __tileHeight;
        
        var _tilesetTexture = tileset_get_texture(__tileset);
        var _tilesetUVs     = tileset_get_uvs(    __tileset);
        var _surfaceWidth  = (_tilesetUVs[2] - _tilesetUVs[0]) / texture_get_texel_width( _tilesetTexture);
        var _surfaceHeight = (_tilesetUVs[3] - _tilesetUVs[1]) / texture_get_texel_height(_tilesetTexture);
        
        var _surface = surface_create(_surfaceWidth, _surfaceHeight);
        surface_set_target(_surface);
        draw_clear_alpha(c_black, 0.0);
        
        //Draw the raw tileset to the surface
        draw_primitive_begin_texture(pr_trianglestrip, _tilesetTexture);
        draw_vertex_texture_colour(            0,              0, 0, 0, c_white, 1.0);
        draw_vertex_texture_colour(            0, _surfaceHeight, 0, 1, c_white, 1.0);
        draw_vertex_texture_colour(_surfaceWidth,              0, 1, 0, c_white, 1.0);
        draw_vertex_texture_colour(_surfaceWidth, _surfaceHeight, 1, 1, c_white, 1.0);
        draw_primitive_end();
        
        //Erase gutters
        gpu_set_blendmode(bm_subtract);
        draw_set_colour(c_white);
        draw_set_alpha(1.0);
        
        var _x = 0;
        repeat(__tilesWide)
        {
            draw_line(_x, -1, _x, _surfaceHeight);
            draw_line(_x+1, -1, _x+1, _surfaceHeight);
            _x += _extTileWidth;
            draw_line(_x-2, -1, _x-2, _surfaceHeight);
            draw_line(_x-1, -1, _x-1, _surfaceHeight);
        }
        
        var _y = 0;
        repeat(__tilesHigh)
        {
            draw_line(-1, _y, _surfaceWidth, _y);
            draw_line(-1, _y+1, _surfaceWidth, _y+1);
            _y += _extTileHeight;
            draw_line(-1, _y-2, _surfaceWidth, _y-2);
            draw_line(-1, _y-1, _surfaceWidth, _y-1);
        }
        
        gpu_set_blendmode(bm_normal);
        
        surface_reset_target();
        
        //Turn the surface into a buffer for analysis
        var _buffer = buffer_create(4*_surfaceWidth*_surfaceHeight, buffer_fixed, 1);
        buffer_get_surface(_buffer, _surface, 0);
        buffer_seek(_buffer, buffer_seek_start, 0);
        surface_free(_surface);
        
        return _buffer;
    }
    
    static __EnsureTag = function()
    {
        if (!BULB_SPRITE_EDGE_AUTOTAG || (__BULB_BUILD_TYPE != "run")) return;
        
        var _tilesetName = tileset_get_name(__tileset);
        var _path = global.__bulbProjectDirectory + "tilesets/" + _tilesetName + "/" + _tilesetName + ".yy";
        
        if (!file_exists(_path))
        {
            __BulbError("Could not find \"", _path, "\"\nTileset was ", _tilesetName, " (index ", __tileset, ")");
            return;
        }
        
        var _buffer = buffer_load(_path);
        var _string = buffer_read(_buffer, buffer_text);
        buffer_delete(_buffer);
        
        var _pos = string_pos("  \"tags\": [", _string);
        if (_pos <= 0)
        {
            _string = string_insert("\n  \"tags\": [\n    \"" + BULB_AUTOTRACE_TAG + "\",\n  ],", _string, string_length(_string)-2);
            
            var _buffer = buffer_create(string_byte_length(_string), buffer_fixed, 1);
            buffer_write(_buffer, buffer_text, _string);
            buffer_save(_buffer, _path);
            buffer_delete(_buffer);
        }
        else if (string_pos_ext("\"" + BULB_AUTOTRACE_TAG + "\"", _string, _pos) <= 0)
        {
            _string = string_insert("    \"" + BULB_AUTOTRACE_TAG + "\",", _string, _pos+12);
            
            var _buffer = buffer_create(string_byte_length(_string), buffer_fixed, 1);
            buffer_write(_buffer, buffer_text, _string);
            buffer_save(_buffer, _path);
            buffer_delete(_buffer);
        }
    }
}