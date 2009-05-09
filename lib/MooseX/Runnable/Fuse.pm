use MooseX::Declare;
use Fuse;

role Filesystem::Fuse::Readable {
    use MooseX::Types::Moose qw(HashRef ArrayRef Defined Int);
    use MooseX::Types::Path::Class qw(File Dir);
    use MooseX::AttributeHelpers;
    use POSIX qw(ENOENT EISDIR);

    require MooseX::Getopt;

    has 'open_files' => (
        traits    => ['NoGetopt'],
        is        => 'ro',
        isa       => HashRef[HashRef[Defined]],
        default   => sub { {} },
        required  => 1,
    );

    requires 'getattr';
    requires 'readlink';
    requires 'getdir';
    requires 'read';
    requires 'statfs';
    requires 'file_exists';

    method open(File $file does coerce, Int $flags){
	return -ENOENT() unless $self->file_exists($file);
	return -EISDIR() if [$self->getattr($file)]->[3] & 0040;
        $self->open_files->{$file->stringify}{$flags} = 1;
        return 0;
    }

    method flush(File $file does coerce) {
        return 0;
    }

    method release(File $file does coerce, Int $flags){
        delete $self->open_files->{$file->stringify}{$flags};
        delete $self->open_files->{$file->stringify} if
          keys %{$self->open_files->{$file->stringify}} < 1;
        return 0;
    }
}

role MooseX::Runnable::Fuse with MooseX::Getopt {
    use MooseX::Types::Moose qw(Bool);
    use MooseX::Types::Path::Class qw(Dir);

    has 'mountpoint' => (
        is       => 'ro',
        isa      => Dir,
        required => 1,
        coerce   => 1,
    );

    has 'debug' => (
        init_arg => 'debug',
        reader   => 'is_debug',
        isa      => Bool,
        default  => sub { 0 },
        required => 1,
    );

    method run {
        my $class = $self->meta;
        my @method_map;

        my $subify = sub {
            my $method = shift;
            return sub { $self->$method(@_) };
        };

        if($class->does_role('Filesystem::Fuse::Readable')){
            push @method_map, map { $_ => $subify->($_) } qw{
                getattr readlink getdir open read
                release statfs flush
            };
        }

        return Fuse::main( # no idea what the return value actually means
            debug      => $self->is_debug ? 1 : 0,
            mountpoint => $self->mountpoint->stringify,
            @method_map,
        );

    }
}

1;
