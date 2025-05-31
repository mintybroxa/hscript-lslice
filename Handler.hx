package;

import sys.io.File;
import sys.FileSystem;
import hscript.Parser;
import hscript.Interp;
import haxe.Serializer;
import haxe.Unserializer;

class ScriptHandler {
    public var interp:Interp;
    var cache:Map<String, Dynamic>;

    public function new() {
        interp = new Interp();
        cache = new Map();
    }

    // Função principal para carregar
    public function load(path:String):Dynamic {
        if (cache.exists(path)) {
            return cache.get(path);
        }

        var hxPath = path + ".hx";
        var hxcPath = path + ".hxc";

        if (FileSystem.exists(hxcPath)) {
            trace('Carregando do cache $hxcPath');
            var data = File.getContent(hxcPath);
            var unserialized = Unserializer.run(data);
            cache.set(path, unserialized);
            return unserialized;
        }

        if (FileSystem.exists(hxPath)) {
            trace('Compilando $hxPath');
            var code = File.getContent(hxPath);
            var parser = new Parser();
            var expr = parser.parseString(code);

            var result = interp.execute(expr);

            saveCache(path, result);
            cache.set(path, result);
            return result;
        }

        throw 'Script $path não encontrado.';
    }

    // Salvar no .hxc
    function saveCache(path:String, value:Dynamic):Void {
        var hxcPath = path + ".hxc";
        try {
            var serialized = Serializer.run(value);
            File.saveContent(hxcPath, serialized);
            trace('Salvo cache em $hxcPath');
        } catch(e) {
            trace('Falha ao salvar cache: $e');
        }
    }

    // Forçar recarregar e atualizar cache
    public function reload(path:String):Dynamic {
        cache.remove(path);
        return load(path);
    }

    // Limpar cache da memória
    public function clearCache():Void {
        cache = new Map();
    }
}
