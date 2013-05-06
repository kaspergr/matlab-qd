classdef OxfordSCPI < handle
    properties
        link_func
    end
    methods
        function obj = OxfordSCPI(link_func)
        % con = OxfordSCPI(link_func)
        %
        % link_func should be a function handle to a function taking a single 
        % string argument (the request) and returning a string (the reply).
            obj.link_func = link_func;
        end
        
        function value = read(obj, prop, varargin)
            p = inputParser();
            p.addOptional('read_format', '%s');
            p.parse(varargin{:});
            read_format = p.Result.read_format;

            rep = obj.link_func(['READ:' prop]);
            parts = qd.util.strsplit(rep, ':');
            
            % check the reply
            qd.util.assert(strcmp(parts{1}, 'STAT'));
            expected = strcat(parts{2:end-1}, ':');
            qd.util.assert(strcmp(expected, prop));
            
            value = qd.util.match(parts{end}, read_format);
        end
        
        function set(obj, prop, value)
            qd.util.assert(ischar(value));
            req = ['SET:' prop ':' value];
            rep = obj.link_func(req);
            qd.util.assert(strcmp(rep, ['STAT:' req ':VALID']));
        end
    end
end