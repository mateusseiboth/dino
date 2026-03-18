dependencies = [
    dep_gio,
    dep_glib,
    dep_libgcrypt,
]
sources = files(
    'src/cipher.vala',
    'src/cipher_converter.vala',
    'src/error.vala',
    'src/random.vala',
)
if dep_libsrtp2.found()
    dependencies += [dep_libsrtp2]
    sources += files('src/srtp.vala')
endif
c_args = [
    '-DG_LOG_DOMAIN="crypto-vala"',
]
vala_args = [
    '--vapidir', meson.current_source_dir() / 'vapi',
]
lib_crypto_vala = library('crypto-vala', sources, c_args: c_args, vala_args: vala_args, dependencies: dependencies, version: '0.0', install: true, install_dir: [true, true, true], install_rpath: default_install_rpath)
dep_crypto_vala = declare_dependency(link_with: lib_crypto_vala, include_directories: include_directories('.'))

install_data('crypto-vala.deps', install_dir: get_option('datadir') / 'vala/vapi', install_tag: 'devel') # TODO: workaround for https://github.com/mesonbuild/meson/issues/9756
