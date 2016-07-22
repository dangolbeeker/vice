% @hidden
-module(evic_prv_imagemagick).
-compile([{parse_transform, lager_transform}]).

%% API
-export([
         init/0
         , infos/2
         , info/3
         , convert/6
        ]).

-record(state, {
          convert,
          identify
         }).

-define(INFOS, "~s -format \"~s\" \"~ts\"").

init() ->
  case evic_utils:find_executable(["convert"], [evic, imagemagick, convert]) of
    undefined ->
      {stop, convert_not_found};
    Convert ->
      case evic_utils:find_executable(["identify"], [evic, imagemagick, identify]) of
        undefined ->
          {stop, identify_not_found};
        Identify ->
          {ok, #state{
                  convert = Convert,
                  identify = Identify
                 }}
      end
  end.

infos(#state{identify = Identify}, File) ->
  {ok, #{
     file_size => get_info(Identify, "%b", File, undefined),
     filename => get_info(Identify, "%f", File, undefined),
     page_geometry => get_info(Identify, "%g", File, undefined),
     height => get_info(Identify, "%h", File, fun bucs:to_integer/1),
     unique_colors => get_info(Identify, "%k", File, undefined),
     file_format => get_info(Identify, "%m", File, undefined),
     number_of_images_in_sequence => get_info(Identify, "%n", File, fun bucs:to_integer/1),
     image_index => get_info(Identify, "%p", File, fun bucs:to_integer/1),
     quantum_depth => get_info(Identify, "%q", File, fun bucs:to_integer/1),
     scene_number => get_info(Identify, "%s", File, fun bucs:to_integer/1),
     width => get_info(Identify, "%w", File, fun bucs:to_integer/1),
     x_resolution => get_info(Identify, "%x", File, fun bucs:to_integer/1),
     y_resolution => get_info(Identify, "%y", File, fun bucs:to_integer/1),
     depth => get_info(Identify, "%z", File, fun bucs:to_integer/1),
     compression_type => get_info(Identify, "%C", File, undefined),
     page_height => get_info(Identify, "%H", File, fun bucs:to_integer/1),
     compression_quality => get_info(Identify, "%Q", File, fun bucs:to_integer/1),
     time_delay => get_info(Identify, "%T", File, fun bucs:to_integer/1),
     resolution_unit => get_info(Identify, "%U", File, undefined),
     page_width => get_info(Identify, "%W", File, fun bucs:to_integer/1),
     page_x_offset => get_info(Identify, "%X", File, fun bucs:to_integer/1),
     page_y_offset => get_info(Identify, "%Y", File, fun bucs:to_integer/1)
    }}.

info(_, _, _) ->
  {error, unavailable}.

get_info(Identify, Attr, File, Fun) ->
  Cmd = lists:flatten(io_lib:format(?INFOS, [Identify, Attr, File])),
  case bucos:run(Cmd) of
    {ok, Data} ->
      case Fun of
        undefined -> Data;
        _ -> erlang:apply(Fun, [Data])
      end;
    _ ->
      undefined
  end.

convert(#state{convert = Convert}, In, Out, Options, Fun, From) ->
  case Fun of
    sync ->
      ok;
    _ ->
      gen_server:reply(From, {async, self()})
  end,
  Cmd = gen_command(Convert, In, Out, Options),
  lager:info("COMMAND : ~p", [Cmd]),
  case bucos:run(Cmd) of
    {ok, _} -> 
      case Fun of
        F when is_function(F, 1) ->
          erlang:apply(Fun, [{ok, In, Out}]);
        sync ->
          gen_server:reply(From, {ok, In, Out});
        _ ->
          ok
      end;
    Error ->
      case Fun of
        F when is_function(F, 1) ->
          erlang:apply(Fun, [Error]);
        sync ->
          gen_server:reply(From, Error);
        _ ->
          ok
      end
  end,
  gen_server:cast(evic, {terminate, self()}).

gen_command(Convert, In, Out, Options) ->
  format("~s \"~ts\" ~s \"~ts\"", [Convert, In, options(Options), Out]).

options(Options) ->
  option(Options, []).

option([], Acc) ->
  string:join(lists:reverse(Acc), " ");

option([{resize, P, percent}|Rest], Acc) ->
  option(Rest, [format("-resize ~w%", [P])|Acc]);
option([{resize, P, pixels}|Rest], Acc) ->
  option(Rest, [format("-resize ~w@", [P])|Acc]);
option([{resize, W, H}|Rest], Acc) ->
  option(Rest, [format("-resize ~wx~w", [W, H])|Acc]);
option([{resize, W, H, percent}|Rest], Acc) ->
  option(Rest, [format("-resize ~w%x~w%", [W, H])|Acc]);
option([{resize, W, H, ignore_ration}|Rest], Acc) ->
  option(Rest, [format("-resize ~wx~w\\!", [W, H])|Acc]);
option([{resize, W, H, no_enlarge}|Rest], Acc) ->
  option(Rest, [format("-resize ~wx~w\\<", [W, H])|Acc]);
option([{resize, W, H, no_shrink}|Rest], Acc) ->
  option(Rest, [format("-resize ~wx~w\\>", [W, H])|Acc]);
option([{resize, W, H, fill}|Rest], Acc) ->
  option(Rest, [format("-resize ~wx~w\\^", [W, H])|Acc]);

option([{thumbnail, P, percent}|Rest], Acc) ->
  option(Rest, [format("-thumbnail ~w%", [P])|Acc]);
option([{thumbnail, P, pixels}|Rest], Acc) ->
  option(Rest, [format("-thumbnail ~w@", [P])|Acc]);
option([{thumbnail, W, H}|Rest], Acc) ->
  option(Rest, [format("-thumbnail ~wx~w", [W, H])|Acc]);
option([{thumbnail, W, H, percent}|Rest], Acc) ->
  option(Rest, [format("-thumbnail ~w%x~w%", [W, H])|Acc]);
option([{thumbnail, W, H, ignore_ration}|Rest], Acc) ->
  option(Rest, [format("-thumbnail ~wx~w\\!", [W, H])|Acc]);
option([{thumbnail, W, H, no_enlarge}|Rest], Acc) ->
  option(Rest, [format("-thumbnail ~wx~w\\<", [W, H])|Acc]);
option([{thumbnail, W, H, no_shrink}|Rest], Acc) ->
  option(Rest, [format("-thumbnail ~wx~w\\>", [W, H])|Acc]);
option([{thumbnail, W, H, fill}|Rest], Acc) ->
  option(Rest, [format("-thumbnail ~wx~w\\^", [W, H])|Acc]);

option([{crop, W, H, X, Y}|Rest], Acc) ->
  option(Rest, [format("-crop ~wx~w+~w+~w +repage", [W, H, X, Y])|Acc]);
option([{crop, W, H}|Rest], Acc) ->
  option(Rest, [format("-gravity center -crop ~wx~w+0+0 +repage", [W, H])|Acc]);

option([_|Rest], Acc) ->
  option(Rest, Acc).

format(FMT, Args) ->
  lists:flatten(io_lib:format(FMT, Args)).
