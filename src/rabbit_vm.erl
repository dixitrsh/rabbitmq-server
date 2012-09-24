%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is VMware, Inc.
%% Copyright (c) 2007-2012 VMware, Inc.  All rights reserved.
%%

-module(rabbit_vm).

-export([memory/0]).

%%----------------------------------------------------------------------------

-ifdef(use_specs).

-spec(memory/0 :: () -> rabbit_types:infos()).

-endif.

%%----------------------------------------------------------------------------

%% Like erlang:memory(), but with awareness of rabbit-y things
memory() ->
    ConnChs = sup_memory(rabbit_tcp_client_sup),
    Qs = sup_memory(rabbit_amqqueue_sup) +
        sup_memory(rabbit_mirror_queue_slave_sup),
    Mnesia = mnesia_memory(),
    MsgIndexETS = ets_memory(rabbit_msg_store_ets_index),
    MsgIndexProc = pid_memory(msg_store_transient) +
        pid_memory(msg_store_persistent),
    MgmtDbETS = ets_memory(rabbit_mgmt_db),
    MgmtDbProc = sup_memory(rabbit_mgmt_sup),
    [{total,     Total},
     {processes, Processes},
     {ets,       ETS},
     {atom,      Atom},
     {binary,    Bin},
     {code,      Code},
     {system,    System}] =
        erlang:memory([total, processes, ets, atom, binary, code, system]),
    [{total,                    Total},
     {connection_channel_procs, ConnChs},
     {queue_procs,              Qs},
     {other_proc,               Processes - ConnChs - Qs - MsgIndexProc -
          MgmtDbProc},
     {mnesia,                   Mnesia},
     {mgmt_db,                  MgmtDbETS + MgmtDbProc},
     {msg_index,                MsgIndexETS + MsgIndexProc},
     {other_ets,                ETS - Mnesia - MsgIndexETS - MgmtDbETS},
     {binary,                   Bin},
     {code,                     Code},
     {atom,                     Atom},
     {other_system,             System - ETS - Atom - Bin - Code}].

%%----------------------------------------------------------------------------

sup_memory(Sup) ->
    lists:sum([child_memory(P, T) || {_, P, T, _} <- sup_children(Sup)]) +
        pid_memory(Sup).

sup_children(Sup) ->
    rabbit_misc:with_exit_handler(
      rabbit_misc:const([]), fun () -> supervisor:which_children(Sup) end).

pid_memory(Pid)  when is_pid(Pid)   -> element(2, process_info(Pid, memory));
pid_memory(Name) when is_atom(Name) -> case whereis(Name) of
                                           P when is_pid(P) -> pid_memory(P);
                                           _                -> 0
                                       end.

child_memory(Pid, worker)     when is_pid (Pid) -> pid_memory(Pid);
child_memory(Pid, supervisor) when is_pid (Pid) -> sup_memory(Pid);
child_memory(_, _)                              -> 0.

mnesia_memory() ->
    lists:sum([bytes(mnesia:table_info(Tab, memory)) ||
                  Tab <- mnesia:system_info(tables)]).

ets_memory(Name) ->
    lists:sum([bytes(ets:info(T, memory)) || T <- ets:all(),
                                             N <- [ets:info(T, name)],
                                             N =:= Name]).

bytes(Words) ->  Words * erlang:system_info(wordsize).
