use strict;
use warnings;
use IO::File;
use JSON::PP;
use Storable qw(dclone);
use stkutils::file::graph;
use stkutils::level::level_gct;

sub read_bin {
    my ($p) = @_;
    open my $f, '<:raw', $p or die "$p: $!";
    local $/; return <$f>;
}
sub write_bin {
    my ($p, $data) = @_;
    open my $f, '>:raw', $p or die "$p: $!";
    print $f $data; close $f;
}
sub graph {
    my $data = read_bin($_[0]);
    my $g = stkutils::file::graph->new(\$data);
    $g->decompose(); $g->read_vertices(); $g->read_edges(); $g->read_level_points();
    die 'Expected SoC graph' unless $g->{gg_version} eq 'soc';
    return $g;
}
my ($base_path, $donor_path, $ct_path, $out_graph, $out_ct, $report) = @ARGV;
die 'Expected base graph, donor graph, donor GCT, output graph, output GCT, report' unless $report;
my $base = graph($base_path);
my $donor = graph($donor_path);
die 'Base already contains dead_city' if $base->{level_by_name}{dead_city};
my $lev = $donor->{level_by_name}{dead_city} or die 'Donor has no dead_city';
die 'Level ID occupied' if $base->{level_by_id}{$lev->{level_id}};
my $first = $lev->{vertex_index};
my $count = $lev->{vertex_count};
my $next = scalar @{$base->{vertices}};
die 'Unexpected donor topology' unless $count == 78;
my $base_guid = $base->{header}{guid};
my @old_vertices = map { dclone($_) } @{$base->{vertices}};
my @edges;
for my $v (@{$base->{vertices}}) {
    push @edges, [map { dclone($base->{edges}[$v->{edge_index}+$_]) } 0..$v->{edge_count}-1];
}
my @added;
for my $old ($first..$first+$count-1) {
    my $src = $donor->{vertices}[$old];
    my $v = dclone($src);
    my @list;
    for my $i (0..$src->{edge_count}-1) {
        my $e = dclone($donor->{edges}[$src->{edge_index}+$i]);
        next if $e->{game_vertex_id} < $first || $e->{game_vertex_id} >= $first+$count;
        $e->{game_vertex_id} += $next-$first;
        push @list, $e;
    }
    $v->{level_point_index} = scalar @{$base->{level_points}};
    for my $i (0..$src->{level_point_count}-1) {
        push @{$base->{level_points}}, dclone($donor->{level_points}[$src->{level_point_index}+$i]);
    }
    push @added, $v; push @edges, \@list;
}
# Keep every vanilla vertex ID and GUID. Add a reciprocal simulation connection.
my $mil = 1848;
die 'Wrong military boundary' unless $base->{vertices}[$mil]{level_id} == 11;
my $dc = $next+1;
for my $pair ([$mil,$dc],[$dc,$mil]) {
    my $e = gg_edge->new();
    $e->{game_vertex_id} = $pair->[1]; $e->{distance} = 100;
    push @{$edges[$pair->[0]]}, $e;
}
push @{$base->{vertices}}, @added;
my @flat;
for my $i (0..$#{$base->{vertices}}) {
    my $v = $base->{vertices}[$i];
    $v->{edge_index} = scalar @flat; $v->{edge_count} = scalar @{$edges[$i]};
    push @flat, @{$edges[$i]};
}
$base->{edges} = \@flat;
my $new_level = dclone($lev);
$new_level->{vertex_index} = $next;
$new_level->{edge_count} = 0;
$new_level->{edge_count} += $_->{edge_count} for @added;
push @{$base->{levels}}, $new_level;
for my $field (qw(level_count vertex_count edge_count level_point_count)) {
    my %arrays = (level_count=>'levels',vertex_count=>'vertices',edge_count=>'edges',level_point_count=>'level_points');
    $base->{header}{$field} = scalar @{$base->{$arrays{$field}}};
}
die 'Graph GUID changed' unless $base->{header}{guid} eq $base_guid;
for my $i (0..$#old_vertices) {
    for my $key (qw(level_id level_vertex_id)) {
        die "Vanilla vertex $i changed" unless $old_vertices[$i]{$key} == $base->{vertices}[$i]{$key};
    }
    die "Vanilla position $i changed" unless join(',',@{$old_vertices[$i]{level_point}}) eq join(',',@{$base->{vertices}[$i]{level_point}});
}
$base->{edges_offset} = $base->{header}{vertex_count} * $base->vertex_block_size();
$base->{level_points_offset} = $base->{header}{edge_count} * $base->edge_block_size();
$base->write_vertices(); $base->write_edges(); $base->write_level_points(); $base->compose();
write_bin($out_graph, ${$base->{data}});
my $ct_data = read_bin($ct_path);
my $ct = stkutils::level::level_gct->new(\$ct_data); $ct->read('full');
die 'GCT/level graph GUID mismatch' unless $ct->{header}{level_guid} eq $lev->{guid};
for my $cell (@{$ct->{cells}}) {
    die 'GCT vertex outside donor level' unless $cell->{game_vertex_id} >= $first && $cell->{game_vertex_id} < $first+$count;
    $cell->{game_vertex_id} += $next-$first;
}
$ct->{header}{game_guid} = $base_guid; $ct->write('full');
write_bin($out_ct, ${$ct->get_data()});
my $info = {
    first_vertex=>$next, vertex_count=>$count, level_id=>$lev->{level_id},
    graph_guid=>unpack('H*',$base_guid), level_guid=>unpack('H*',$lev->{guid}),
    entry_lv=>479935, entry_gv=>$ct->{cells}[479935]{game_vertex_id},
    vertices=>[map { {gv=>$next+$_, lv=>$added[$_]{level_vertex_id}, position=>$added[$_]{level_point}} } 0..$#added],
};
write_bin($report, JSON::PP->new->canonical->pretty->encode($info));
print "Dead City appended: ID=$lev->{level_id}, vertices=$next..",$next+$count-1,"; all original vertex IDs preserved\n";
