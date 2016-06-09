use Modern::Perl;
use Data::Dump;

use MediaWiki::API;

binmode STDOUT, ":utf8";

my $mw = MediaWiki::API->new();
$mw->{config}->{api_url} = 'http://linux-sunxi.org/api.php';

# Infobox may have any of the following, some field may not be present
my @infobox_fields = qw(image caption manufacturer dimensions release_date website soc dram emmc nand power lcd touchscreen video audio network storage usb camera other headers);

my $not_template_re = qr/(?> .*? (?= (?:\}\}) | (?:\{\{) ) )/x;
my $template_re = qr/\{\{ (?: $not_template_re | (?0) )* \}\}/x;
my $link_re = qr/\[ (?: [^\[\]]* | (?0) )* \]/x; # May be [[link]]...
my $infobox_re = qr/\{\{ \s* Infobox \s+ Board \s* \| ( (?: $not_template_re | $template_re )* ) \}\}/x;

sub parse_infobox {
	my ($body) = @_;

	# Linebreaks make life harder, don't provide information
	$body =~ s/\n/ /g;

	my ($infobox) = $body =~ $infobox_re;

	# Split by field, <field> -> <key> = <content>, <infobox> -> <field> | <field> ...
	# Can't use a basic split, as there may be templates or links containing | inside the content
	#
	# Could do balanced matching again, but it is even messier than above
	# Instead we cheat and rewrite the string to simplify things, then do a basic parse
	
	my $infobox_rewrite = $infobox;
	$infobox_rewrite =~ s/$template_re/" " x length($&)/ge;
	$infobox_rewrite =~ s/$link_re/" " x length($&)/ge;

	my %infobox_elems;
	my $start = 0;
	do {
		my $end = index($infobox_rewrite, "|", $start);
		my $field = eval {
			return substr($infobox, $start, $end-$start) if ($end > 0);
			return substr($infobox, $start);
		};
		my ($key, $content) = $field =~ /\s* (\w+) \s* = \s* (.*?) \s*$/x;

		if ($key ~~ @infobox_fields) {
			$infobox_elems{$key}=$content;
		} else {
			$infobox_elems{"warning"} .= "$_ is not a valid infobox field";
		}

		$start = $end+1;
	} while ($start);

	return \%infobox_elems;
}

my $articles = $mw->list ( {
    action => 'query',
    list => 'categorymembers',
    cmtitle => 'Category:Devices',
    cmlimit => 'max'
} ) || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};


say(join("\t", qw/title pageid revid timestamp/, @infobox_fields, "warnings"));

foreach (@{$articles}) {
	my $title = $_->{title};
	next if $title =~ /Category:/;
	my $page = $mw->get_page( { title => $title } );

	my $body = $page->{'*'};

	my %dict = %{parse_infobox($body)};

	my @out = ($title, $page->{pageid}, $page->{revid}, $page->{timestamp});
	push(@out, $dict{$_} // "") foreach (@infobox_fields, "warning");
	say(join("\t", @out));
}
